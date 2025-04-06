local M = {}
local util = require("oz.util")

M.status_win = nil
M.status_buf = nil

M.state = {}
M.status_grab_buffer = {}

-- hl
local function status_buf_hl()
	vim.cmd("syntax clear")

	vim.api.nvim_set_hl(0, "ozInactivePrompt", { fg = "#757575" })
	vim.fn.matchadd("@error", "^\\s\\+deleted:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("WarningMsg", "^\\s\\+both modified:\\s\\+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("MoreMsg", "^\\s\\+modified:\\s\\+.*$", 0, -1, { extend = true })

	vim.api.nvim_set_hl(0, "OzGitDiffPlus", { fg = "#000000", bg = "#A0C878" })
	vim.api.nvim_set_hl(0, "OzGitDiffMinus", { fg = "#000000", bg = "#E17564" })
	vim.fn.matchadd("OzGitDiffPlus", "^    +.*$", 0, -1, { extend = true })
	vim.fn.matchadd("OzGitDiffMinus", "^    -.*$", 0, -1, { extend = true })

	-- stash and heading
	vim.cmd([[
        syntax match ozInactivePrompt /stash@{[0-9]}/ "stash
        syntax match @function /^[A-Z][^ \t].*/ "heading
        syn region @boolean matchgroup=Delimiter start="\[" end="\]"
    ]])

	-- commit hash
	vim.cmd("syntax match ozgitstatusCommitHash '\\<[0-9a-f]\\{7,40}\\>' containedin=ALL")
	vim.cmd("highlight default link ozgitstatusCommitHash ozInactivePrompt")

	-- branch
	vim.cmd([[
        syntax match ozGitStatusHeader "^On branch " nextgroup=ozGitStatusBranchName
        syntax match ozGitStatusBranchName "\S\+" contained
        syntax match ozGitStatusCurBranch /\*\s\w\+/

        highlight default link ozGitStatusBranchName Title
        highlight default link ozGitStatusCurBranch Title
        highlight default link ozGitStatusHeader @function
    ]])

	-- remote branch
	vim.cmd([[
        highlight GitStatusLine guifg=#808080 ctermfg=244
        highlight GitStatusQuoted guifg=#99BC85 ctermfg=46 gui=bold
        highlight default link GitStatusNumber @warning

        syntax match GitStatusLine /^Your branch is .*$/
        syntax match GitStatusQuoted /'[^']*'/ contained containedin=GitStatusLine
        syntax match GitStatusNumber /\d\+/ contained containedin=GitStatusLine
    ]])
end

-- status buf FileType
local function status_buf_ft()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "GitStatus",
		once = true,
		callback = function(event)
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			-- load async
			vim.fn.timer_start(0, function()
				status_buf_hl()
			end)
			vim.fn.timer_start(100, function()
				require("oz.git.status.keymaps").keymaps_init(event.buf)
			end)
		end,
	})
end

-- create and open the status
local function open_status_buf(lines)
	if M.status_buf == nil or not vim.api.nvim_win_is_valid(M.status_win) then
		M.status_buf = vim.api.nvim_create_buf(false, true)

		vim.cmd("botright split")
		M.status_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(M.status_win, M.status_buf)

		vim.api.nvim_buf_set_lines(M.status_buf, 0, -1, false, lines)

		status_buf_ft()
		vim.api.nvim_buf_set_option(M.status_buf, "ft", "GitStatus")

		vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
			buffer = M.status_buf,
			callback = function()
				M.status_buf = nil
				M.status_win = nil
			end,
		})
	else
		vim.api.nvim_set_current_win(M.status_win)
		vim.api.nvim_buf_set_option(M.status_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.status_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.status_buf, "modifiable", false)
	end
end

local function is_conflict(lines)
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
	local status_str = util.ShellOutputList("git status")
	local stash_str = util.ShellOutputList("git stash list")

	if #status_str ~= 0 then
		for _, substr in ipairs(status_str) do
			if substr ~= "" and not substr:match('%(use "git .-.%)') then
				-- substr = substr:gsub("^[%s\t]+", " ")
				table.insert(status_tbl, substr)
			end
		end
	end

	if #stash_str ~= 0 then
		table.insert(status_tbl, "Stash list:")
		for _, substr in ipairs(stash_str) do
			if substr ~= "" and not substr:match('%(use "git .-.%)') then
				table.insert(status_tbl, "\t" .. substr)
			end
		end
	end
	return status_tbl
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
	M.state.current_branch = util.ShellOutput("git branch --show-current")
	local lines = generate_status_content()

	open_status_buf(lines)
	M.state.in_conflict = is_conflict(lines)
	s_util.get_heading_tbl(lines)
end

return M
