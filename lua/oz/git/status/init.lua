local M = {}
local g_util = require("oz.git.util")
local shell = require("oz.util.shell")
local win = require("oz.util.win")

M.status_win = nil
M.status_buf = nil

M.state = {}
M.status_grab_buffer = {}

-- CONFIGURATION
M.icons = {
	collapsed = "",
	expanded = "",
}

-- The Order in which sections are rendered
M.render_order = { "branch", "staged", "unstaged", "untracked", "worktrees", "stash" }

-- Template Configuration
local section_template = {
	branch = { header = "Branch: ", default_collapsed = true },
	staged = { header = "Staged changes", default_collapsed = false },
	unstaged = { header = "Unstaged changes", default_collapsed = false },
	untracked = { header = "Untracked", default_collapsed = true },
	worktrees = { header = "Worktrees", default_collapsed = false },
	stash = { header = "Stashes", default_collapsed = false },
}

M.state = {
	cwd = nil,
	current_branch = nil,
	sections = {},
	info_lines = {},
	in_conflict = false,
}

local function format_git_line(code, file)
	local map = {
		["M"] = "modified:   ",
		["A"] = "new file:   ",
		["D"] = "deleted:    ",
		["R"] = "renamed:    ",
		["C"] = "copied:     ",
		["U"] = "unmerged:   ",
		["?"] = "",
	}
	local prefix = map[code] or "modified:   "
	-- Changed \t to "  " for alignment with header text
	return "  " .. prefix .. file
end

local function generate_status_info(current_branch, in_conflict)
	local info = {}
	local root_path = g_util.get_project_root()

	if in_conflict then
		table.insert(info, "[!] Merge Conflict Detected")
	end

	if current_branch == "HEAD" or current_branch:match("HEAD detached") then
		table.insert(info, "[!] HEAD is detached")
	end

	if current_branch ~= "HEAD" then
		local ok, counts = shell.run_command({ "git", "rev-list", "--left-right", "--count", "HEAD...@{u}" }, root_path)
		if ok and #counts > 0 then
			local ahead, behind = counts[1]:match("(%d+)%s+(%d+)")
			if ahead and behind then
				local parts = {}
				if tonumber(ahead) > 0 then
					table.insert(parts, "Ahead " .. ahead)
				end
				if tonumber(behind) > 0 then
					table.insert(parts, "Behind " .. behind)
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
	local _, branch_res = shell.run_command({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, root_path)
	local current_branch = branch_res[1] or "HEAD"
	M.state.current_branch = current_branch

	new_sections.branch.header = "Branch: " .. current_branch

	local _, branch_list = shell.run_command({ "git", "branch", "-vv" }, root_path)
	for _, line in ipairs(branch_list) do
		if line ~= "" then
			-- "  " aligns with text after icon
			table.insert(new_sections.branch.content, "  " .. line)
		end
	end

	-- 3. Worktrees Section (Only show if >= 2)
	local wt_ok, wt_out = shell.run_command({ "git", "worktree", "list", "--porcelain" }, root_path)
	if wt_ok then
		local worktree_items = {}
		local current_wt = {}

		-- Helper to finalize a worktree item
		local function push_wt()
			if current_wt.path then
				table.insert(worktree_items, {
					path = current_wt.path,
					sha = current_wt.sha or "",
					branch = current_wt.branch or "detached",
				})
			end
		end

		for _, line in ipairs(wt_out) do
			if line:match("^worktree") then
				push_wt()
				current_wt = { path = line:sub(10) }
			elseif line:match("^HEAD") then
				current_wt.sha = line:sub(6, 12)
			elseif line:match("^branch") then
				current_wt.branch = line:match("refs/heads/(.*)")
			end
		end
		push_wt() -- Push last one

		-- Only render if we have more than 1 worktree (main + others)
		if #worktree_items >= 2 then
			for _, item in ipairs(worktree_items) do
				-- Added "  " prefix for alignment
				local display = string.format("  %s  %s [%s]", item.path, item.sha, item.branch)
				table.insert(new_sections.worktrees.content, display)
			end
		else
			-- Ensure content is empty so renderer skips it (or hides header based on logic)
			new_sections.worktrees.content = {}
		end
	end

	-- 4. Git Status --porcelain
	local status_ok, status_out = shell.run_command({ "git", "status", "--porcelain" }, root_path)
	if status_ok then
		for _, line in ipairs(status_out) do
			if line ~= "" then
				local x = line:sub(1, 1)
				local y = line:sub(2, 2)
				local file = line:sub(4)

				if x ~= " " and x ~= "?" then
					table.insert(new_sections.staged.content, format_git_line(x, file))
				end

				if y ~= " " and y ~= "?" then
					table.insert(new_sections.unstaged.content, format_git_line(y, file))
				end

				if x == "?" and y == "?" then
					-- Changed \t to "  "
					table.insert(new_sections.untracked.content, "  " .. file)
				end
			end
		end
	end

	-- 5. Git Stash
	local stash_ok, stash_out = shell.run_command({ "git", "stash", "list" }, root_path)
	if stash_ok then
		for _, line in ipairs(stash_out) do
			if line ~= "" then
				-- Changed \t to "  "
				table.insert(new_sections.stash.content, "  " .. line)
			end
		end
	end

	return new_sections
end

local function status_buf_hl()
	vim.cmd("syntax clear")

	-- Define Colors
	vim.api.nvim_set_hl(0, "ozInactivePrompt", { fg = "#757575" })
	vim.api.nvim_set_hl(0, "ozGitStatusHeading", { fg = "#ffffff", bold = true })

	-- Regex Matches for Content
	vim.fn.matchadd("healthError", "^\\s\\+deleted:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("healthWarning", "^\\s\\+both modified:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@field", "^\\s\\+modified:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("healthSuccess", "^\\s\\+new file:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@diff.plus", "^    +.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@diff.minus", "^    -.*$", 0, -1, { extend = true })

	-- Branch Content Highlights
	vim.cmd([[
    syntax match ozGitStatusBranchName "\S\+" contained
    highlight default link ozGitStatusBranchName @attribute
    syntax match @attribute /\*\s\w\+/
    ]])

	-- Stash
	vim.cmd("syntax match ozInactivePrompt /stash@{[0-9]}/")
	vim.cmd("syntax match ozInactivePrompt '\\<[0-9a-f]\\{7,40}\\>' containedin=ALL")

	-- Misc
	vim.cmd([[
    syn region @property matchgroup=Delimiter start="\[" end="\]"
    syntax match String /'[^']*'/ containedin=ALL
    syntax match Number /\s\d\+/ containedin=ALL
    ]])
end

local function is_conflict(sections)
	for _, line in ipairs(sections.unstaged.content or {}) do
		if line:match("unmerged:") then
			return true
		end
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

	pcall(vim.api.nvim_win_set_cursor, 0, pos)
	vim.cmd("checktime")
end

function M.GitStatus()
	local s_util = require("oz.git.status.util")

	M.state.cwd = vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd()

	M.state.sections = generate_sections()
	M.state.in_conflict = is_conflict(M.state.sections)
	M.state.info_lines = generate_status_info(M.state.current_branch, M.state.in_conflict)

	win.create_win("status", {
		content = {},
		win_type = "bot",
		callback = function(buf_id, win_id)
			M.status_buf = buf_id
			M.status_win = win_id

			vim.cmd([[setlocal ft=oz_git signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.opt_local.fillchars:append({ eob = " " })

			s_util.render(buf_id)

			vim.fn.timer_start(10, function()
				status_buf_hl()
			end)
			vim.fn.timer_start(100, function()
				require("oz.git.status.keymaps").keymaps_init(buf_id)
			end)
		end,
	})
end

return M
