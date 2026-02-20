local M = {}
local g_util = require("oz.git.util")
local util = require("oz.util")

M.status_win = nil
M.status_buf = nil

M.state = {}
M.status_grab_buffer = {}

M.icons = {
	collapsed = "",
	expanded = "",
}

-- The Order in which sections are rendered
M.render_order = { "branch", "staged", "unstaged", "untracked", "worktrees", "stash" }

-- Template Configuration
local section_template = {
	branch = { header = "Branch: ", default_collapsed = true },
	staged = { header = "Staged", default_collapsed = false },
	unstaged = { header = "Unstaged", default_collapsed = false },
	untracked = { header = "Untracked", default_collapsed = false },
	worktrees = { header = "Worktrees", default_collapsed = false },
	stash = { header = "Stashes", default_collapsed = false },
}

M.state = {
	cwd = nil,
	current_branch = nil,
	sections = {},
	worktree_map = {},
	info_lines = {},
	in_conflict = false,
	line_map = {},
}

local function generate_status_info(current_branch, in_conflict)
	local info = {}
	local root_path = g_util.get_project_root()

	local ok, git_dir_res = util.run_command({ "git", "rev-parse", "--git-dir" }, root_path)
	if ok and git_dir_res[1] then
		local git_dir = git_dir_res[1]
		if not git_dir:match("^/") then
			git_dir = root_path .. "/" .. git_dir
		end
		git_dir = vim.trim(git_dir)

		if vim.fn.filereadable(git_dir .. "/MERGE_HEAD") == 1 then
			table.insert(info, "[!] Merging")
		end

		if vim.fn.filereadable(git_dir .. "/CHERRY_PICK_HEAD") == 1 then
			table.insert(info, "[!] Cherry-picking")
		end

		if vim.fn.filereadable(git_dir .. "/REVERT_HEAD") == 1 then
			table.insert(info, "[!] Reverting")
		end

		if
			vim.fn.isdirectory(git_dir .. "/rebase-merge") == 1
			or vim.fn.isdirectory(git_dir .. "/rebase-apply") == 1
		then
			table.insert(info, "[!] Rebasing")
		end

		if vim.fn.filereadable(git_dir .. "/BISECT_LOG") == 1 then
			table.insert(info, "[!] Bisecting")
		end
	end

	if in_conflict then -- conflict
		table.insert(info, "[!] Merge Conflict Detected")
	elseif current_branch == "HEAD" or current_branch:match("HEAD detached") then -- detached head
		table.insert(info, "[!] HEAD is detached")
	elseif current_branch ~= "HEAD" then -- ahead/behind
		local c_ok, counts =
			util.run_command({ "git", "rev-list", "--left-right", "--count", "HEAD...@{u}" }, root_path)
		if c_ok and #counts > 0 then
			local ahead, behind = counts[1]:match("(%d+)%s+(%d+)")
			if ahead and behind then
				local parts = {}
				if tonumber(ahead) > 0 then
					table.insert(parts, string.format("[] %d commit ahead", ahead))
				end
				if tonumber(behind) > 0 then
					table.insert(parts, string.format("[] %d commit behind", behind))
				end

				if #parts > 0 then
					table.insert(info, table.concat(parts, ", "))
				end
			end
		end
	end
	return info
end

--- PARSER
local function generate_sections()
	local root_path = g_util.get_project_root()

	-- 1. Initialize sections
	local new_sections = {}
	for key, config in pairs(section_template) do
		local is_collapsed = config.default_collapsed
		if M.state.sections[key] and M.state.sections[key].collapsed ~= nil then
			is_collapsed = M.state.sections[key].collapsed
		end

		new_sections[key] = {
			header = config.header,
			collapsed = is_collapsed,
			content = {},
		}
	end

	-- 2. Branch Section
	local ok, branch_res = util.run_command({ "git", "branch", "--show-current" }, root_path)
	local current_branch = (ok and branch_res[1]) or "HEAD"
	M.state.current_branch = current_branch
	new_sections.branch.header = "Branch: " .. current_branch

	local _, branch_list = util.run_command({ "git", "branch", "-vv" }, root_path)
	for _, line in ipairs(branch_list) do
		if line ~= "" then
			table.insert(new_sections.branch.content, { type = "branch_item", text = line })
		end
	end

	-- 3. Worktrees Section
	M.state.worktree_map = {} -- Reset Map
	local wt_ok, wt_out = util.run_command({ "git", "worktree", "list" }, root_path)
	if wt_ok then
		local worktree_items = {}
		for _, line in ipairs(wt_out) do
			local path, sha, rest = line:match("^(%S+)%s+(%x+)%s+(.*)$")
			if path then
				local branch_name = rest:match("%[(.-)%]")
				local is_prunable = rest:match("prunable")

				local status = is_prunable and "(prunable)" or ""

				-- EXTRACT SHORT NAME
				local short_name = path:match("([^/]+)$") or path

				-- STORE MAPPING (Short Name -> Full Path)
				M.state.worktree_map[short_name] = path

				table.insert(worktree_items, {
					name = short_name,
					sha = sha,
					branch = branch_name or "detached",
					status = status,
				})
			end
		end

		if #worktree_items >= 2 then
			for _, item in ipairs(worktree_items) do
				table.insert(new_sections.worktrees.content, {
					type = "worktree",
					name = item.name,
					branch = item.branch,
					sha = item.sha,
					status = item.status,
				})
			end
		else
			new_sections.worktrees.content = {}
		end
	end

	-- 4. Git Status --porcelain
	local status_ok, status_out = util.run_command({ "git", "status", "--porcelain" }, root_path)
	if status_ok then
		for _, line in ipairs(status_out) do
			if line ~= "" then
				local x, y, file = line:sub(1, 1), line:sub(2, 2), line:sub(4)
				if x ~= " " and x ~= "?" then
					table.insert(new_sections.staged.content, { type = "file", status = x, path = file })
				end
				if y ~= " " and y ~= "?" then
					table.insert(new_sections.unstaged.content, { type = "file", status = y, path = file })
				end
				if x == "?" and y == "?" then
					table.insert(new_sections.untracked.content, { type = "file", status = "?", path = file })
				end
			end
		end
	end

	-- 5. Git Stash
	local stash_ok, stash_out = util.run_command({ "git", "stash", "list" }, root_path)
	if stash_ok then
		for _, line in ipairs(stash_out) do
			if line ~= "" then
				table.insert(new_sections.stash.content, { type = "stash", raw = line })
			end
		end
	end

	return new_sections
end

local function status_buf_hl()
	vim.cmd("syntax clear")
	util.setup_hls({
		"ozInactivePrompt",
		"ozGitStatusHeading",
		{ ozGitStatusBranchName = "@attribute" },
	})

	-- Consolidate all patterns into buffer-local syntax matches.
	-- We use a list of pairs to allow multiple patterns for the same highlight group.
	vim.fn.matchadd("healthError", "^deleted:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("healthWarning", "^both modified:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@field", "^modified:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("healthSuccess", "^new file:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@diff.plus", "^+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@diff.minus", "^-.*$", 0, -1, { extend = true })
    vim.cmd([[
        syntax match ozGitStatusBranchName "\S\+" contained
        syntax match @attribute /\*\s\S\+/
        syntax match ozInactivePrompt /stash@{[0-9]}/
        syn region @property matchgroup=Delimiter start="\[" end="\]"
        syntax match String /'[^']*'/ containedin=ALL
        syntax match Number /\s\d\+/ containedin=ALL
    ]])
    vim.cmd("syntax match ozInactivePrompt '\\<[0-9a-f]\\{7,40}\\>' containedin=ALL")
end

local function is_conflict(sections)
	local root_path = g_util.get_project_root()
	local ok, out = util.run_command({ "git", "diff", "--name-only", "--diff-filter=U" }, root_path)
	if ok and #out > 0 then
		return true
	end
	return false
end

function M.refresh_buf(passive)
	local s_util = require("oz.git.status.util")
	local pos = vim.api.nvim_win_get_cursor(0)
	if not passive then
		vim.cmd("lcd " .. M.state.cwd)
		M.state.sections = generate_sections()
		M.state.in_conflict = is_conflict(M.state.sections)
		M.state.info_lines = generate_status_info(M.state.current_branch, M.state.in_conflict)
	end
	s_util.render(M.status_buf)
	require("oz.git.status.keymaps").keymaps_init(M.status_buf)
	pcall(vim.api.nvim_win_set_cursor, 0, pos)
	pcall(vim.cmd.checktime)
end

function M.GitStatus()
	local s_util = require("oz.git.status.util")
	M.state.cwd = g_util.get_project_root()
	M.state.sections = generate_sections()
	M.state.in_conflict = is_conflict(M.state.sections)
	M.state.info_lines = generate_status_info(M.state.current_branch, M.state.in_conflict)
	local win_type = require("oz.git").user_config.win_type or "botright"

	vim.fn.sign_define("OzGitStatusExpanded", { text = M.icons.expanded, texthl = "ozInactivePrompt" })
	vim.fn.sign_define("OzGitStatusCollapsed", { text = M.icons.collapsed, texthl = "ozInactivePrompt" })

	util.create_win("status", {
		content = {},
		win_type = win_type,
		buf_name = "OzGitStatus",
		callback = function(buf_id, win_id)
			M.status_buf = buf_id
			M.status_win = win_id
            vim.cmd(
                [[setlocal ft=oz_git signcolumn=yes listchars= nonumber norelativenumber nowrap nomodifiable bufhidden=wipe]]
            )

			vim.opt_local.fillchars:append({ eob = " " })

			vim.cmd("lcd " .. M.state.cwd)
			s_util.render(buf_id)

			vim.fn.timer_start(10, function()
				status_buf_hl()
			end)
			vim.fn.timer_start(100, function()
				require("oz.git.status.keymaps").keymaps_init(buf_id)
			end)

			vim.api.nvim_create_autocmd("BufDelete", {
				buffer = buf_id,
				callback = function()
					require("oz.git.status.inline_diff").cleanup(buf_id)
				end,
			})
		end,
	})
end

return M
