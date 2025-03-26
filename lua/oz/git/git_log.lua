local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")

local log_win = nil
local log_buf = nil
local log_win_height = 14

local log_level = 1
local comming_from = nil
local user_set_args = nil
local grab_hashs = {}

local function get_curline_hash()
	local line = vim.api.nvim_get_current_line()
	for hash in line:gmatch("[0-9a-f]%w[0-9a-f]%w[0-9a-f]%w[0-9a-f]+") do
		if #hash >= 7 and #hash <= 40 then
			return hash
		end
	end
	return nil
end

-- awesome stuff
local function log_buf_keymaps(buf)
	-- close
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "close git log buffer." })

	-- increase log level
	vim.keymap.set("n", ">", function()
		vim.cmd("close")
		log_level = (log_level % 3) + 1
		M.commit_log({ level = log_level, from = comming_from })
	end, { remap = false, buffer = buf, silent = true, desc = "increase log level." })

	-- decrease log level
	vim.keymap.set("n", "<", function()
		vim.cmd("close")
		local log_levels = { [1] = 3, [2] = 1, [3] = 2 }
		log_level = log_levels[log_level]
		M.commit_log({ level = log_level, from = comming_from })
	end, { remap = false, buffer = buf, silent = true, desc = "decrease log level." })

	-- back
	vim.keymap.set("n", "<C-o>", function()
		if comming_from then
			vim.cmd("close")
			vim.cmd(comming_from)
		end
	end, { remap = false, buffer = buf, silent = true, desc = "go back." })

	-- custom user args
	vim.keymap.set("n", "g:", function()
		local input = util.UserInput("args:")
		if input then
			vim.cmd("close")
			M.commit_log({ level = 1 }, { input })
		end
	end, { remap = false, buffer = buf, silent = true, desc = "add args to log command." })

	-- :Git
	vim.keymap.set("n", "g<space>", ":Git ", { remap = false, buffer = buf, desc = "open :Git " })

	-- pick hash
	vim.keymap.set("n", "<C-g>", function()
		local hash = get_curline_hash()
		if hash then
			util.tbl_insert(grab_hashs, hash)
			vim.notify_once("press a/i to enter cmdline, <C-c> to reset.")

			g_util.start_monitoring(grab_hashs, {
				interval = 2000,
				buf = buf,
				on_active = function(t)
					vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
				end,
			})
		end
	end, { buffer = buf, silent = true, desc = "pick any valid entry under cursor." })

	-- edit picked
	vim.keymap.set("n", "a", function()
		if #grab_hashs ~= 0 then
			require("oz.git").after_exec_complete(function(code, stdout)
				if code == 0 and #stdout == 0 then
					M.refresh_commit_log()
				end
			end)
			g_util.stop_monitoring(grab_hashs)
			g_util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
			grab_hashs = {}
		end
	end, { buffer = buf, silent = true, desc = "enter cmdline to edit picked hashes." })

	vim.keymap.set("n", "i", function()
		if #grab_hashs ~= 0 then
			require("oz.git").after_exec_complete(function(code, stdout)
				if code == 0 and #stdout == 0 then
					M.refresh_commit_log()
				end
			end)
			g_util.stop_monitoring(grab_hashs)
			g_util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
			grab_hashs = {}
		end
	end, { buffer = buf, silent = true, desc = "enter cmdline to edit picked hashes." })

	-- refresh
	vim.keymap.set("n", "<C-r>", function()
		M.refresh_commit_log()
		g_util.toggle_monitoring(grab_hashs)
	end, { buffer = buf, silent = true, desc = "refresh commit log buffer." })

	-- discard picked
	vim.keymap.set("n", "<C-c>", function()
		g_util.stop_monitoring(grab_hashs)

		grab_hashs = #grab_hashs > 0 and {} or grab_hashs
		vim.api.nvim_echo({ { "" } }, false, {})
		util.Notify("All picked hashes have been removed.", nil, "oz_git")
	end, { buffer = buf, silent = true, desc = "discard any picked hashes." })

	-- show current hash
	vim.keymap.set("n", "<cr>", function()
		local hash = get_curline_hash()
		if hash then
			vim.cmd("Git show " .. hash)
		end
	end, { buffer = buf, silent = true, desc = "show current hash under cursor." })

	-- help
	vim.keymap.set("n", "g?", function()
		util.Show_buf_keymaps()
	end, { remap = false, buffer = buf, silent = true, desc = "show all availble keymaps." })
end

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
			log_buf_keymaps(event.buf)
			log_buf_hl()
		end,
	})
	return true
end

local function open_commit_log_buf(lines)
	if log_buf == nil or not vim.api.nvim_win_is_valid(log_win) then
		log_buf = vim.api.nvim_create_buf(false, true)

		vim.cmd("botright " .. log_win_height .. " split")
		log_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(log_win, log_buf)

		vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, lines)

		if log_buf_ft() then
			vim.api.nvim_buf_set_option(log_buf, "ft", "GitLog")
		else
			vim.api.nvim_buf_set_option(log_buf, "ft", "oz_git")
		end

		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = log_buf,
			callback = function()
				log_buf = nil
				log_win = nil
			end,
		})
	else
		vim.api.nvim_set_current_win(log_win)
		vim.cmd("resize " .. log_win_height)
		vim.api.nvim_buf_set_option(log_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(log_buf, "modifiable", false)
	end
end

local function get_commit_log_lines(level, args)
	local commit_log_tbl = {}
	local log = nil
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
		log = vim.fn.systemlist("git log " .. table.concat(args, " ") .. " " .. fmt_flags)
	elseif user_set_args and user_set_args ~= "" then
		log = vim.fn.systemlist("git log " .. table.concat(user_set_args, " ") .. " " .. fmt_flags)
		vim.api.nvim_echo({ { ":Git log " }, { table.concat(user_set_args, " "), "@attribute" } }, false, {})
	else
		log = vim.fn.systemlist("git log " .. fmt_flags)
	end

	local function process_line(line)
		if line ~= "" then
			if line:find("%*") then
				if line:find("HEAD -") then
					line = line:gsub("%*", "@")
				end
			end
			table.insert(commit_log_tbl, line)
		end
	end

	-- Process each line in the log
	for _, line in ipairs(log) do
		process_line(line)
	end
	return commit_log_tbl
end

function M.refresh_commit_log()
	local pos = vim.api.nvim_win_get_cursor(0)
	vim.cmd("close")
	M.commit_log({ level = log_level, from = comming_from })
	pcall(vim.api.nvim_win_set_cursor, 0, pos)
end

function M.commit_log(opts, args)
	local level
	if opts then
		comming_from = opts.from
		level = opts.level
	end
	local commit_logs_line = get_commit_log_lines(level, args)
	open_commit_log_buf(commit_logs_line)
end

return M
