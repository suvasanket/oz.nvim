local M = {}
local util = require("oz.util")
local shell = require("oz.util.shell")
local win = require("oz.util.win")

M.log_win = nil
M.log_buf = nil
local commit_log_lines = nil

M.log_level = 1
M.comming_from = nil
M.grab_hashs = {}
M.state = {}
local user_set_args = nil

local shellout_tbl = shell.shellout_tbl
local run_cmd = shell.run_command

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

local function add_cherrypick_icon(log)
	local picked_hashes = shellout_tbl("git rev-parse --verify --quiet --short CHERRY_PICK_HEAD", M.state.cwd)
	if #picked_hashes == 0 then
		return log
	else
		local logg = {}
		for _, line in ipairs(log) do
			local picked_hash = util.str_in_tbl(line, picked_hashes)
			if picked_hash then
				line = line:gsub(picked_hash, picked_hash .. " 🍒")
			end
			table.insert(logg, line)
		end
		return logg
	end
end

local function get_commit_log_lines(level, args)
	local log, fmt_flags, ok
	if level == 2 then
		fmt_flags = {
			"--graph",
			"--abbrev-commit",
			"--decorate",
			"--format=format:%h - %aD [%ar]%d%n          %s - %an",
		}
	elseif level == 3 then
		fmt_flags = {
			"--graph",
			"--abbrev-commit",
			"--decorate",
			"--format=format:%h - %aD [%ar] [committed: %cD] %d%n          %s%n          - %an <%ae> [committer: %cn <%ce>]",
		}
	else
		fmt_flags = {
			"--graph",
			"--abbrev-commit",
			"--decorate",
			"--format=format:%h - [%ar] %s - %an%d",
		}
	end
	if args and #args > 0 then
		user_set_args = args
		ok, log = run_cmd({ "git", "log", unpack(args), unpack(fmt_flags) }, M.state.cwd)
	elseif user_set_args and user_set_args ~= "" then
		ok, log = run_cmd({ "git", "log", unpack(user_set_args), unpack(fmt_flags) }, M.state.cwd)
	else
		ok, log = run_cmd({ "git", "log", unpack(fmt_flags) }, M.state.cwd)
	end

	log = add_cherrypick_icon(log)

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

	M.state.cwd = vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd()

	vim.cmd("lcd " .. (vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd())) -- change cwd to project
	commit_log_lines = get_commit_log_lines(level, args)

	-- open log
	win.open_win("log", {
		lines = commit_log_lines,
        win_type = "bot",
		callback = function(buf_id, win_id)
			M.log_buf = buf_id
			M.log_win = win_id

			-- opts
            vim.cmd([[setlocal ft=oz_git signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])

			-- async component
			vim.fn.timer_start(10, function()
				log_buf_hl()
			end)
			vim.fn.timer_start(100, function()
				require("oz.git.git_log.keymaps").keymaps_init(buf_id)
			end)
		end,
	})
end

return M
