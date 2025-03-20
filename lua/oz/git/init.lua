local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local wizard = require("oz.git.wizard")

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

local function run_git_command(args)
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
			suggestion = wizard.parse_git_suggestion(data, cmd)
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						table.insert(std_err, line)
					end
				end
			end
			suggestion = wizard.parse_git_suggestion(data, cmd)
		end,
		on_exit = function()
			if is_remote and #std_err == 0 then -- remote dependant
				util.Notify(complete, nil, "oz_git")
			elseif cmd == "commit" then
				wizard.commit_wizard()
			elseif #std_out ~= 0 then
				g_util.open_output_split(std_out)
			elseif #std_err ~= 0 then
				g_util.open_output_split(std_err)
			end
			if suggestion then
				util.Notify("press enter to continue with suggestion.", nil, "oz_git")
				vim.api.nvim_feedkeys(":Git " .. suggestion, "n", false)
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
		-- oz_git ft..
		require("oz.git.oz_git_ft").oz_git_hl()
		-- git cmd
		run_git_command(opts.args)
	end, { nargs = "+" })
end

return M
