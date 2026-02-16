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

-- get selected or current SHA under cursor
---@return table
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
	end

	for _, line in ipairs(lines) do
		for hash in line:gmatch("[0-9a-f]%w[0-9a-f]%w[0-9a-f]%w[0-9a-f]+") do
			if #hash >= 7 and #hash <= 40 then
				util.tbl_insert(entries, hash)
			end
		end
	end

	if vim.api.nvim_get_mode().mode == "n" then
		return { entries[1] }
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

	vim.cmd([[
    syntax match Comment /\*\w\+/ containedin=ALL
    syntax match Comment /\zs\*\w\+\ze.\{-}\*\w\+/ skipwhite
    ]])
end

local function add_cherrypick_icon(content)
	local picked_hashes = shellout_tbl("git rev-parse --verify --quiet --short CHERRY_PICK_HEAD", M.state.cwd)
	if #picked_hashes == 0 then
		return content
	else
		local logg = {}
		for _, line in ipairs(content) do
			local picked_hash = util.str_in_tbl(line, picked_hashes)
			if picked_hash then
				line = line:gsub(picked_hash, picked_hash .. " 🍒")
			end
			table.insert(logg, line)
		end
		return logg
	end
end

local function generate_content(level, args)
	local content, fmt_flags, ok
	if level == 2 then
		fmt_flags = {
			"--graph",
			"--abbrev-commit",
			"--decorate",
			"--format=format:%h - %aD [%ar]%d%n          %s *%an",
		}
	elseif level == 3 then
		fmt_flags = {
			"--graph",
			"--abbrev-commit",
			"--decorate",
			"--format=format:%h - %aD [%ar] [committed: %cD] %d%n          %s%n          *%an <%ae> [committer: %cn <%ce>]",
		}
	else
		fmt_flags = {
			"--graph",
			"--abbrev-commit",
			"--decorate",
			"--format=format:%h - [%ar] %s *%an%d",
		}
	end
	if args and #args > 0 then
		user_set_args = args
		ok, content = run_cmd({ "git", "log", unpack(args), unpack(fmt_flags) }, M.state.cwd)
	elseif user_set_args and user_set_args ~= "" then
		ok, content = run_cmd({ "git", "log", unpack(user_set_args), unpack(fmt_flags) }, M.state.cwd)
	else
		ok, content = run_cmd({ "git", "log", "--all", unpack(fmt_flags) }, M.state.cwd) -- default show all.
	end

	content = add_cherrypick_icon(content)

	if ok then
		return content
	else
		return {}
	end
end

function M.refresh_buf(passive)
	if passive then
		local lines = generate_content()
		vim.api.nvim_set_option_value("modifiable", true, { buf = M.log_buf })
		vim.api.nvim_buf_set_lines(M.log_buf, 0, -1, false, lines)
		vim.api.nvim_set_option_value("modifiable", false, { buf = M.log_buf })
	else
		local pos = vim.api.nvim_win_get_cursor(0)
		M.commit_log({ from = M.comming_from })
		pcall(vim.api.nvim_win_set_cursor, 0, pos)
	end
	pcall(vim.cmd.checktime)
end

-- commit log
---@param opts table|nil
---@param args table|nil
function M.commit_log(opts, args)
	local level
	if opts then
		M.comming_from = opts.from
		level = opts.level
	end
	local win_type = (opts and opts.win_type) or require("oz.git").user_config.win_type or "tab"

	M.state.cwd = vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd()

	vim.cmd("lcd " .. (vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd())) -- change cwd to project
	commit_log_lines = generate_content(level, args)

	-- open log
	win.create_win("log", {
		content = commit_log_lines,
		win_type = win_type,
		buf_name = "OzGitLog",
		callback = function(buf_id, win_id)
			M.log_buf = buf_id
			M.log_win = win_id

			-- opts
			vim.cmd(
				[[setlocal ft=oz_git signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable bufhidden=wipe]]
			)
			vim.opt_local.fillchars:append({ eob = " " })

			-- async component
			vim.fn.timer_start(10, function()
				log_buf_hl()
			end)
			vim.fn.timer_start(100, function()
				require("oz.git.log.keymaps").keymaps_init(buf_id)
			end)
		end,
	})
end

return M
