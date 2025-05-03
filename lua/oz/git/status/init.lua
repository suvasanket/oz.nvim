local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local shell = require("oz.util.shell")
local win = require("oz.util.win")

local run_cmd = shell.run_command

M.status_win = nil
M.status_buf = nil

M.state = {}
M.status_grab_buffer = {}

-- hl
local function status_buf_hl()
	vim.cmd("syntax clear")

	vim.api.nvim_set_hl(0, "ozInactivePrompt", { fg = "#757575" })
	vim.fn.matchadd("healthError", "^\\s\\+deleted:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("healthWarning", "^\\s\\+both modified:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@field", "^\\s\\+modified:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("healthSuccess", "^\\s\\+new file:\\s\\+.*$", 0, -1, { extend = true })

	vim.fn.matchadd("@diff.plus", "^    +.*$", 0, -1, { extend = true })
	vim.fn.matchadd("@diff.minus", "^    -.*$", 0, -1, { extend = true })

	-- heading
	vim.cmd([[
        syntax match ozInactivePrompt /^[a-z][^ \t].*/
        syntax match Bold /^[A-Z][^ \t].*/
        highlight ozGitStatusHeading guifg=#ffffff ctermfg=46 gui=bold

        syntax match ozGitStatusHeading "^On branch " nextgroup=ozGitStatusBranchName
        syntax match ozGitStatusHeading "^Stash list:"
        syntax match ozGitStatusHeading "^Changes not staged for commit:"
        syntax match ozGitStatusHeading "^Untracked files:"
        syntax match ozGitStatusHeading "^Changes to be committed:"
    ]])

	-- inactive
	vim.cmd("syntax match ozInactivePrompt /stash@{[0-9]}/")
	vim.cmd("syntax match ozInactivePrompt '\\<[0-9a-f]\\{7,40}\\>' containedin=ALL")

	-- branch
	vim.cmd([[
        syntax match ozGitStatusBranchName "\S\+" contained

        highlight default link ozGitStatusBranchName @attribute
        syntax match @attribute /\*\s\w\+/
        syntax match ozInactivePrompt /^.*Your branch.*$/
    ]])

	-- misc
	vim.cmd([[
        syn region @boolean matchgroup=Delimiter start="\[" end="\]"
        syntax match String /'[^']*'/
        syntax match Number /\d\+/
    ]])
end

local function is_conflict(lines) -- FIXME
	for _, line in pairs(lines) do
		if
			line:match("both modified:")
			or line:match("both added:")
			or line:match("added by us:")
			or line:match("added by them:")
			or line:match("deleted by us:")
			or line:match("deleted by them:")
			or line:match("unmerged:")
			or line:match("Unmerged paths:")
		then
			return true
		end
	end
	return false
end

-- get neccessry lines for status buffer
local function generate_status_content()
	local status_tbl = {}
	local stash_tbl = {}
	local git_root = g_util.get_project_root()
	local status_ok, git_status_output = run_cmd({ "git", "status" }, git_root)
	local stash_ok, git_stash_output = run_cmd({ "git", "stash", "list" }, git_root)

	if status_ok and #git_status_output > 0 then
		for _, line in ipairs(git_status_output) do
			if not line:match('%(use "git .-.%)') then
				table.insert(status_tbl, line)
			end
		end
		if not status_tbl[2]:match("Your branch") then
			table.insert(status_tbl, 2, "")
		end
	end

	if stash_ok and #git_stash_output > 0 then
		table.insert(stash_tbl, "Stash list:")
		for _, substr in ipairs(git_stash_output) do
			if substr ~= "" and not substr:match('%(use "git .-.%)') then
				table.insert(stash_tbl, "\t" .. substr)
			end
		end
	end
	if status_tbl[#status_tbl] ~= "" then
		table.insert(status_tbl, "")
	end
	return util.join_tables(status_tbl, stash_tbl)
end

local function get_toggled_headings(tbl1, tbl2)
	local result = {}
	for _, f_key in pairs(tbl1) do
		for s_key, _ in pairs(tbl2) do
			if string.find(f_key, s_key:match("^(.-) ")) then
				util.tbl_insert(result, s_key)
			end
		end
	end

	return result
end

function M.refresh_status_buf(passive)
	local s_util = require("oz.git.status.util")
	if passive then -- passive refresh
		local lines = generate_status_content()
		vim.api.nvim_buf_set_option(M.status_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.status_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.status_buf, "modifiable", false)

		s_util.get_heading_tbl(lines)

		-- retoggle any user toggeled headings
		local toggled_headings = get_toggled_headings(s_util.toggeled_headings, s_util.headings_table)
		for _, item in ipairs(toggled_headings) do
			s_util.toggle_section(item)
		end
	else -- active
		local pos = vim.api.nvim_win_get_cursor(0)
		vim.fn.timer_start(0, function()
			vim.cmd("lcd " .. M.state.cwd)

			-- recall status
			M.GitStatus()

			-- retoggle any user toggeled headings
			local toggled_headings = get_toggled_headings(s_util.toggeled_headings, s_util.headings_table)
			for _, item in ipairs(toggled_headings) do
				s_util.toggle_section(item)
			end

			pcall(vim.api.nvim_win_set_cursor, 0, pos)
		end)
	end
end

-- Initialize status
function M.GitStatus()
	local s_util = require("oz.git.status.util")

	M.state.cwd = vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd()
	local _, branch = run_cmd({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, M.state.cwd)
	M.state.current_branch = branch[1]

	local lines = generate_status_content()

	-- open status
	win.open_win("status", {
		lines = lines,
		win_type = "bot",
		callback = function(buf_id, win_id)
			M.status_buf = buf_id
			M.status_win = win_id

			-- opts
			vim.cmd([[setlocal ft=oz_git signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.opt_local.fillchars:append({ eob = " " })

			-- async component
			vim.fn.timer_start(10, function()
				status_buf_hl()
			end)
			vim.fn.timer_start(100, function()
				require("oz.git.status.keymaps").keymaps_init(buf_id)
			end)
		end,
	})

	M.state.in_conflict = is_conflict(lines)
	s_util.get_heading_tbl(lines)
end

return M
