local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local wizard = require("oz.git.wizard")
local oz_git_win = require("oz.git.oz_git_win")

local function git_commit(args_table)
	if #args_table == 1 then
		local message = util.UserInput("commit message:")

		if message then
			args_table = { "commit", "-m", message }
			return args_table
		else
			return {}
		end
	else
		return args_table
	end
end

function RunGitCmd(args)
	args = g_util.expand_expressions(args)
	local args_table = g_util.parse_args(args)
	local cmd = args_table[1]
	local suggestion = nil
	local std_out = {}
	local std_err = {}

	local is_remote, start, complete = g_util.get_remote_cmd(args_table[1])
	if is_remote then
		util.Notify(start, nil, "oz_git")
	end

	-- commit cmd
	if cmd == "commit" then
		args_table = git_commit(args_table)
		if #args_table == 0 then
			return
		end
	end

	-- help -> man
	if g_util.check_flags(args_table, "help") or g_util.check_flags(args_table, "h") then
		vim.cmd("Man git-" .. cmd)
		return
	end

	---@diagnostic disable-next-line: deprecated
	local job_id = vim.fn.jobstart({ "git", unpack(args_table) }, {
		stdout_buffered = true,
		stderr_buffered = true,
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
		on_exit = function()
			if is_remote and #std_err == 0 then -- remote dependant
				util.Notify(complete, nil, "oz_git")
			elseif cmd == "commit" then
				wizard.commit_wizard()
			elseif #std_out ~= 0 then
				oz_git_win.open_oz_git_win(std_out, args, "stdout")
			elseif #std_err ~= 0 then
				oz_git_win.open_oz_git_win(std_err, args, "stderr")
			end
			if suggestion then
				util.Notify("press enter to continue with suggestion.", nil, "oz_git")
				g_util.set_cmdline("Git " .. suggestion)
			end
		end,
	})

	if job_id <= 0 then
		print("Failed to start job")
	end
end

-- Define the user command
function M.oz_git_usercmd_init()
	vim.api.nvim_create_user_command("Git", function(opts)
		-- git cmd
		RunGitCmd(opts.args)
	end, { nargs = "+" })
end

return M
