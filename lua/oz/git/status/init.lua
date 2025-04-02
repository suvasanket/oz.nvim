local M = {}
local util = require("oz.util")

local status_win = nil
local status_buf = nil
local status_win_height = 14

M.status_grab_buffer = {}
M.current_branch = nil
M.in_conflict = false
CWD = nil

-- hl
local function status_buf_hl()
	vim.cmd("syntax clear")

	vim.cmd([[syntax match ozgitstatusDeleted /^\s\+deleted:\s\+.*$/]])
	vim.cmd([[syntax match ozgitstatusBothModified /^\s\+both modified:\s\+.*$/]])
	vim.cmd([[syntax match ozgitstatusModified /^\s\+modified:\s\+.*$/]])
	vim.api.nvim_set_hl(0, "ozgitstatusDeleted", { fg = "#757575" })
	vim.cmd("highlight default link ozgitstatusModified MoreMsg")
	vim.cmd("highlight default link ozgitstatusBothModified WarningMsg")

	-- diff
	vim.cmd([[
    syntax match ozgitstatusDiffAdded /^    +.\+$/
    syntax match ozgitstatusDiffRemoved /^    -.\+$/
    highlight default link ozgitstatusDiffAdded @diff.plus
    highlight default link ozgitstatusDiffRemoved @diff.minus
    ]])

	-- headings
	vim.cmd([[
    syntax match NoIndentCapital /^[A-Z][^ \t].*/
    highlight link NoIndentCapital @function
    ]])

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
    highlight GitStatusQuoted guifg=#99BC85 ctermfg=46 gui=italic
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
	return true
end

-- create and open the status
local function open_status_buf(lines)
	if status_buf == nil or not vim.api.nvim_win_is_valid(status_win) then
		status_buf = vim.api.nvim_create_buf(false, true)

		vim.cmd("botright " .. status_win_height .. " split")
		status_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(status_win, status_buf)

		vim.api.nvim_buf_set_lines(status_buf, 0, -1, false, lines)

		if status_buf_ft() then
			vim.api.nvim_buf_set_option(status_buf, "ft", "GitStatus")
		else
			vim.api.nvim_buf_set_option(status_buf, "ft", "oz_git")
		end

		vim.fn.timer_start(100, function()
			vim.api.nvim_create_autocmd("BufDelete", {
				buffer = status_buf,
				callback = function()
					status_buf = nil
					status_win = nil
					CWD = nil
				end,
			})
		end)
	else
		vim.api.nvim_set_current_win(status_win)
		vim.cmd("resize " .. status_win_height)
		vim.api.nvim_buf_set_option(status_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(status_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(status_buf, "modifiable", false)
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

function M.refresh_status_buf()
	local pos = vim.api.nvim_win_get_cursor(0)
	vim.fn.timer_start(0, function()
		local s_util = require("oz.git.status.util")
		vim.cmd("lcd " .. CWD)

		-- recall status
		M.GitStatus()

		-- retoggle any user toggeled headings
		local toggled_headings = get_toggled_headings(s_util.opened_headings, s_util.headings_table)
		for _, item in ipairs(toggled_headings) do
			s_util.toggle_section(item)
		end

		pcall(vim.api.nvim_win_set_cursor, 0, pos)
	end)
end

-- Initialize status
function M.GitStatus()
	local s_util = require("oz.git.status.util")

	CWD = vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd()
	M.current_branch = util.ShellOutput("git branch --show-current")
	local lines = generate_status_content()

	M.in_conflict = is_conflict(lines)
	s_util.headings_table = {}
	s_util.get_heading_tbl(lines)
	open_status_buf(lines)
end

return M
