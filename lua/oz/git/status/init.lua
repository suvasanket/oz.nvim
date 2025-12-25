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
	return "  " .. prefix .. file
end

local function generate_status_info(current_branch, in_conflict)
	local info = {}
	local root_path = g_util.get_project_root()

	if in_conflict then -- conflict
		table.insert(info, "[!] Merge Conflict Detected")
	elseif current_branch == "HEAD" or current_branch:match("HEAD detached") then -- detached head
		table.insert(info, "[!] HEAD is detached")
	elseif current_branch ~= "HEAD" then -- ahead/behind
		local ok, counts = shell.run_command({ "git", "rev-list", "--left-right", "--count", "HEAD...@{u}" }, root_path)
		if ok and #counts > 0 then
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
	local _, branch_res = shell.run_command({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, root_path)
	local current_branch = branch_res[1] or "HEAD"
	M.state.current_branch = current_branch

	new_sections.branch.header = "Branch: " .. current_branch

	local _, branch_list = shell.run_command({ "git", "branch", "-vv" }, root_path)
	for _, line in ipairs(branch_list) do
		if line ~= "" then
			table.insert(new_sections.branch.content, "  " .. line)
		end
	end

	-- 3. Worktrees Section
	local wt_ok, wt_out = shell.run_command({ "git", "worktree", "list" }, root_path)
	if wt_ok then
		local worktree_items = {}
		for _, line in ipairs(wt_out) do
			local path, sha, rest = line:match("^(%S+)%s+(%x+)%s+(.*)$")
			if path then
				local branch_name = rest:match("%[(.-)%]")
				local is_prunable = rest:match("prunable")

				local status = ""
				if is_prunable then
					status = "(prunable)"
				end

				local short_name = path:match("([^/]+)$") or path

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
				local display = string.format("  %s(%s) %s %s", item.name, item.branch, item.sha, item.status)
				display = display:gsub("%s+$", "")
				table.insert(new_sections.worktrees.content, display)
			end
		else
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
    syntax match @attribute /\*\s\S\+/
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
