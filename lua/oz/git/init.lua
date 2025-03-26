local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local wizard = require("oz.git.wizard")
local oz_git_win = require("oz.git.oz_git_win")

-- CMD parser
local function different_cmd_runner(args_table, args_str)
	local cmd = args_table[1]

	-- editor
	local req_editor =
		{ "commit", "commit --amend", "tag -a", "rebase -i", "merge --no-commit", "notes add", "filter-branch" }
	local is_req_editor = util.str_in_tbl(args_str, req_editor)
	if is_req_editor then
		if vim.fn.executable("nvr") ~= 1 then
			util.Notify("neovim-remote not found, install it use editor required commands.")
			return true
		end
		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "gitrebase", "gitcommit" },
			callback = function()
				vim.bo.bufhidden = "delete"
			end,
		})
	end

	if cmd == "commit" and #args_table == 1 then
		local changed = vim.fn.systemlist("git diff --name-only --cached")
		if #changed < 1 then
			util.Notify("Nothing to commit.", "error", "oz_git")
			return true
		end
	end

	-- help -> man
	if g_util.check_flags(args_table, "--help") or g_util.check_flags(args_table, "-h") then
		vim.cmd("Man git-" .. cmd)
		return true
	end

	-- remote cmds
	local remote = { "push", "pull", "fetch", "clone", "request-pull", "svn" }
	local is_remote = util.str_in_tbl(cmd, remote)
	if is_remote then
		vim.cmd("hor term git " .. table.concat(args_table, " "))
		if oz_git_win.oz_git_ft() then
			vim.api.nvim_buf_set_option(0, "ft", "oz_git")
		else
			vim.api.nvim_buf_set_option(0, "ft", "git")
		end
		vim.cmd("resize 9")
		vim.api.nvim_buf_set_name(0, "")
		vim.cmd.wincmd("p")
		return true
	end
end

-- callback to run after :Git cmd complete
local exec_complete_callback = nil
function M.after_exec_complete(callback)
	if callback then
		exec_complete_callback = callback
	end
end

-- Run Git cmd
function RunGitCmd(args)
	args = g_util.expand_expressions(args)
	local args_table = g_util.parse_args(args)
	local cmd = args_table[1]
	local suggestion = nil
	local std_out = {}
	local std_err = {}

	if different_cmd_runner(args_table, args) then
		return
	end

	local job_id = vim.fn.jobstart({ "git", unpack(args_table) }, {
		stdout_buffered = true,
		stderr_buffered = true,
		env = {
			GIT_EDITOR = "nvr -cc split --remote-wait",
			GIT_SEQUENCE_EDITOR = "nvr -cc split --remote-wait",
		},
		on_stdout = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						table.insert(std_out, line)
					end
				end
			end
			suggestion = wizard.parse_git_suggestion(data, args_table)
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						table.insert(std_err, line)
					end
				end
			end
			suggestion = wizard.parse_git_suggestion(data, args_table)
		end,
		on_exit = function(_, code, _)
			if code == 0 then
				if cmd == "commit" then
					wizard.commit_wizard()
				elseif #std_out == 1 then
					util.Notify(std_out[1], "info", "oz_git")
				elseif #std_out ~= 0 then
					oz_git_win.open_oz_git_win(std_out, args, "stdout")
				end
			else
				if #std_err == 1 then
					util.Notify(std_err[1], "error", "oz_git")
				elseif #std_err ~= 0 then
					oz_git_win.open_oz_git_win(std_err, args, "stderr")
				end
			end

			if suggestion then
				g_util.set_cmdline("Git " .. suggestion)
			end

			-- run exec complete callbacks
			if exec_complete_callback then
				exec_complete_callback(code, std_out, std_err)
				exec_complete_callback = nil
			end
		end,
	})

	if job_id <= 0 then
		print("Failed to start job")
	end
end

-- Define the user command
function M.oz_git_usercmd_init()
	-- :Git
	vim.api.nvim_create_user_command("Git", function(opts)
		if g_util.if_in_git() then
			if opts.args and #opts.args > 0 then
				RunGitCmd(opts.args)
			else
				require("oz.git.status").GitStatus()
			end
		elseif opts.args and opts.args:find("init") then
			RunGitCmd(opts.args)
		else
			vim.api.nvim_feedkeys(":Git init", "n", false)
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, {
		nargs = "*",
		desc = "oz_git",
		complete = function(arglead, cmdline, cursorpos)
			return require("oz.git.complete").complete(arglead, cmdline, cursorpos)
		end,
	})

	-- log
	vim.api.nvim_create_user_command("GitLog", function(opts)
		if g_util.if_in_git() then
			local args_table = vim.split(opts.args, "%s+")
			require("oz.git.git_log").commit_log({ level = 1 }, args_table)
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", desc = "oz_git log" })

	-- Gr
	vim.api.nvim_create_user_command("Gr", function()
		if g_util.if_in_git() then
			M.after_exec_complete(function()
				vim.cmd("edit")
			end)
			vim.cmd("Git checkout -- %")
			vim.api.nvim_echo({ { ":Git " }, { "checkout -- %", "ModeMsg" } }, false, {})
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", desc = "Git read" })

	-- Gw
	vim.api.nvim_create_user_command("Gw", function()
		if g_util.if_in_git() then
			local ok = pcall(vim.cmd, "w")
			if ok then
				vim.cmd("Git add %")
			end
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", desc = "Git write" })
end

return M
