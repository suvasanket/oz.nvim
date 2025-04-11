local M = {}
local util = require("oz.util")

M.log_win = nil
M.log_buf = nil
local commit_log_lines = nil

M.log_level = 1
M.comming_from = nil
M.grab_hashs = {}
local user_set_args = nil

function M.get_selected_hash()
	local lines = {}
	local entries = {}
	if vim.api.nvim_get_mode().mode == "n" then
		local line = vim.fn.getline(".")
		table.insert(lines, line)
	else
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
		-- vim.api.nvim_input("<Esc>") -- FIXME
	end

	for _, line in ipairs(lines) do
		for hash in line:gmatch("[0-9a-f]%w[0-9a-f]%w[0-9a-f]%w[0-9a-f]+") do
			if #hash >= 7 and #hash <= 40 then
				util.tbl_insert(entries, hash)
			end
		end
	end

	return entries
end

-- highlight
local function log_buf_hl()
	vim.cmd("syntax clear")

	vim.cmd("syntax match ozgitlogCommitHash '\\<[0-9a-f]\\{7,40}\\>' containedin=ALL")
	vim.cmd("highlight default link ozgitlogCommitHash @attribute")

	vim.cmd([[
    syntax region ozGitLogBranchName start=/(/ end=/)/ contains=ALL
    highlight ozGitLogBranchName guifg=#A390F0 guibg=NONE
    ]])

	vim.cmd([[
    syntax match ozGitLogTime /\[.*\]/
    highlight link ozGitLogTime Comment
    ]])

	vim.cmd([[
    syntax match ozGitLogHead /HEAD -> \w\+/
    highlight ozGitLogHead guifg=#A390F0 guibg=NONE gui=bold
    ]])

	vim.cmd([[
    syntax match PathSeparator /\w\+\/\w\+/
    highlight PathSeparator guifg=#99BC85 guibg=NONE gui=italic
    ]])
end

local function log_buf_ft()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "GitLog",
		once = true,
		callback = function(event)
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.fn.timer_start(10, function()
				log_buf_hl()
			end)
			vim.fn.timer_start(100, function()
				require("oz.git.git_log.keymaps").keymaps_init(event.buf)
			end)
		end,
	})
	return true
end

local function open_commit_log_buf(lines)
	if M.log_buf == nil or not vim.api.nvim_win_is_valid(M.log_win) then
		M.log_buf = vim.api.nvim_create_buf(false, true)

		vim.cmd("botright split")
		M.log_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(M.log_win, M.log_buf)

		vim.api.nvim_buf_set_lines(M.log_buf, 0, -1, false, lines)

		if log_buf_ft() then
			vim.api.nvim_buf_set_option(M.log_buf, "ft", "GitLog")
		else
			vim.api.nvim_buf_set_option(M.log_buf, "ft", "oz_git")
		end

		vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
			buffer = M.log_buf,
			callback = function()
				M.log_buf = nil
				M.log_win = nil
			end,
		})
	else
		vim.api.nvim_set_current_win(M.log_win)
		vim.api.nvim_buf_set_option(M.log_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.log_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.log_buf, "modifiable", false)
	end
end

local function get_commit_log_lines(level, args)
	local log = {}
	local fmt_flags
	if level == 2 then
		fmt_flags = "--graph --abbrev-commit --decorate --format=format:'%h - %aD [%ar]%d%n''          %s - %an'"
	elseif level == 3 then
		fmt_flags =
			"--graph --abbrev-commit --decorate --format=format:'%h - %aD [%ar] [committed: %cD] %d%n''          %s%n''          - %an <%ae> [committer: %cn <%ce>]'"
	else
		fmt_flags = "--graph --abbrev-commit --decorate --format=format:'%h - [%ar] %s - %an%d'"
	end
	if args and #args > 0 then
		user_set_args = args
		log = util.ShellOutputList("git log " .. fmt_flags .. " " .. table.concat(args, " "))
	elseif user_set_args and user_set_args ~= "" then
		log = util.ShellOutputList("git log " .. table.concat(user_set_args, " ") .. " " .. fmt_flags)
	else
		log = util.ShellOutputList("git log " .. fmt_flags)
	end

	return log
end

function M.refresh_commit_log(passive)
	if passive then
		local lines = get_commit_log_lines()
		vim.api.nvim_buf_set_option(M.log_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.log_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.log_buf, "modifiable", false)
	else
		local pos = vim.api.nvim_win_get_cursor(0)
		M.commit_log({ from = M.comming_from })
		pcall(vim.api.nvim_win_set_cursor, 0, pos)
	end
end

function M.commit_log(opts, args)
	local level
	if opts then
		M.comming_from = opts.from
		level = opts.level
	end
    vim.cmd("lcd " .. (vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd())) -- change cwd to project
	commit_log_lines = get_commit_log_lines(level, args)
	open_commit_log_buf(commit_log_lines)
end

return M
