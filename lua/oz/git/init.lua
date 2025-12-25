local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local wizard = require("oz.git.wizard")
local oz_git_win = require("oz.git.oz_git_win")
local shell = require("oz.util.shell")
local editor_ipc = require("oz.util.editor")

local editor_req_cmds = {
	"commit",
	"commit --amend",
	"tag -a",
	"rebase -i",
	"merge --no-commit",
	"notes add",
	"filter-branch",
}

M.user_config = nil
M.running_git_jobs = {}
M.state = {}

--- helper: notify or open in window
---@param output table
---@param args string
---@param exit_code number
local function notify_or_open(output, args, exit_code)
	if #output == 0 then
		return
	end
	local notfy_level = exit_code == 0 and "info" or "error"
	if #output <= 1 then
		util.Notify(table.concat(output, "\n"), notfy_level, "oz_git")
	else
		oz_git_win.open_oz_git_win(output, args)
	end
end

--- CMD pareser
---@param args_tbl table
---@param args_str string
---@return boolean
local function special_cmd_exec(args_tbl, args_str)
	local cmd = args_tbl[1]

	if util.str_in_tbl(args_str, editor_req_cmds) then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "gitrebase", "gitcommit", "gitconfig" },
			callback = function(event)
				vim.bo.bufhidden = "delete"
				if vim.bo.ft == "gitrebase" then -- set some cool keymaps for rebase buffer
					wizard.rebase_buf_mappigs(event.buf)
				end
			end,
		})
	end

	local remote_cmds = { "push", "pull", "fetch", "clone", "request-pull", "ls-remote", "submodule", "svn" }
	local interactive_cmd = { "add -p", "add -i", "reset -p", "commit -p", "checkout -p" }

	-- All special cmd exec --
	-- Grep
	if cmd == "grep" then
		table.remove(args_tbl, 1)
		local ok, out = shell.run_command({ "git", "grep", "-n", "--column", unpack(args_tbl) })
		if ok then
			vim.fn.setqflist({}, " ", {
				lines = out,
				efm = "%f:%l:%c:%m",
			})
			if #vim.fn.getqflist() > 0 then
				vim.cmd("cw")
			end
		end
		return true

	-- interactive cmds
	elseif util.str_in_tbl(args_str, interactive_cmd) then
		g_util.run_term_cmd({
			cmd = "git " .. util.str_in_tbl(args_str, interactive_cmd),
			on_exit_callback = function()
				util.Notify("Interactive hunk selection exited.", nil, "oz_git")
			end,
		})

	-- Man cmd
	elseif cmd == "help" or vim.tbl_contains(args_tbl, "--help") then
		local cmd_l = cmd == "help" and args_tbl[2] or cmd
		vim.cmd("Man git-" .. cmd_l)
		return true

    -- Diff cmd
    elseif cmd == "diff" then
        require("oz.git.remote_cmd").run_git_with_progress("diff", args_tbl, function(lines)
            oz_git_win.open_oz_git_win(lines, args_str)
            vim.api.nvim_buf_set_option(0, "filetype", "diff")
        end)
        return true

	-- Progress cmds
	elseif vim.tbl_contains(remote_cmds, cmd) then
		if M.user_config and M.user_config.remote_opt_exec == "background" then -- user config
			local command = table.remove(args_tbl, 1)

			require("oz.git.remote_cmd").run_git_with_progress(command, args_tbl, function(lines)
				oz_git_win.open_oz_git_win(lines, args_str)
				-- git suggestion
				local suggestion = wizard.get_git_suggestions(lines, args_tbl)
				if suggestion then
					util.set_cmdline(suggestion)
				end
			end)
		elseif M.user_config and M.user_config.remote_opt_exec == "term" then -- TODO run in oz_term
			vim.cmd("hor term git " .. table.concat(args_tbl, " "))
			vim.api.nvim_buf_set_option(0, "ft", oz_git_win.oz_git_ft() and "oz_git" or "git")
			vim.cmd("resize 9")
			vim.api.nvim_buf_set_name(0, "")
			vim.cmd.wincmd("p")
		end
		return true
	end
	return false
end

-- callback to run after :Git cmd complete
local exec_complete_callback = nil
local exec_complete_callback_return = false
--- callback func
---@param callback function
---@param ret boolean|nil
function M.after_exec_complete(callback, ret)
	if callback then
		exec_complete_callback = callback
	end
	exec_complete_callback_return = ret or false
end

-- ENV --
local job_env = {}

-- refresh any required buffers.
---@param passive boolean|nil
function M.refresh_buf(passive)
	local status_win = require("oz.git.status").status_win
	local log_win = require("oz.git.log").log_win

	if status_win and vim.api.nvim_win_is_valid(status_win) then
		if passive then
			require("oz.git.status").refresh_buf(true)
		else
			require("oz.git.status").refresh_buf()
		end
	elseif log_win and vim.api.nvim_win_is_valid(log_win) then
		if passive then
			require("oz.git.log").refresh_buf(true)
		else
			require("oz.git.log").refresh_buf()
		end
	end
end

--- remove any running jobs.
---@param args table
function M.cleanup_git_jobs(args)
	if args then
		if args.job_id then
			vim.fn.jobstop(args.job_id)
		end
		if args.cmd then
			for key, job_id in pairs(M.running_git_jobs) do
				if key:match("^" .. args.cmd .. "%d*$") then
					vim.fn.jobstop(job_id)
					M.running_git_jobs[key] = nil
				end
			end
		end
	else
		local killed_any = false
		for name, job_id in pairs(M.running_git_jobs) do
			if vim.fn.jobstop(job_id) == 1 then
				M.running_git_jobs[name] = nil
				killed_any = true
			else
				util.Notify("Failed to stop job: " .. name, "error", "oz_git")
			end
		end

		if not killed_any then
			util.Notify("No tracked Git jobs found to stop.", "error", "oz_git")
		end
	end
end

--- Run Git cmd.
---@param args string
function M.run_git_job(args)
	args = util.args_parser().expand_expressions(args)
	local args_table = util.args_parser().parse_args(args)

    local allowed_cmds = {
        "add", "am", "archive", "bisect", "blame", "branch", "bundle", "checkout", "cherry-pick",
        "clean", "clone", "commit", "config", "describe", "diff", "fetch", "gc", "grep", "init",
        "log", "ls-files", "ls-remote", "ls-tree", "merge", "mv", "notes", "pull", "push",
        "rebase", "reflog", "remote", "reset", "restore", "revert", "rm", "shortlog", "show",
        "stash", "status", "submodule", "switch", "tag", "worktree",
    }

    if not vim.tbl_contains(allowed_cmds, args_table[1]) then
        util.Notify("Command '" .. args_table[1] .. "' is not allowed or supported.", "error", "oz_git")
        return
    end

	local suggestion = nil
	local std_out = {}
	local std_err = {}

	if special_cmd_exec(args_table, args) then
		return
	end

	local current_job_env = job_env
	local ipc_cleanup = nil

	if util.str_in_tbl(args, editor_req_cmds) then
		local env, cleanup = editor_ipc.setup_ipc_env()
		current_job_env = vim.tbl_extend("force", job_env, env)
		ipc_cleanup = cleanup
	end

	if vim.tbl_isempty(current_job_env) then
		current_job_env = nil
	end

	local job_id = vim.fn.jobstart({ "git", unpack(args_table) }, {
		stdout_buffered = true,
		stderr_buffered = true,
		env = current_job_env,
		on_stdout = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						table.insert(std_out, line)
					end
				end
			end
			suggestion = wizard.get_git_suggestions(data, args_table)
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						table.insert(std_err, line)
					end
				end
			end
			suggestion = wizard.get_git_suggestions(data, args_table)
		end,
		on_exit = function(_, code, _)
			if ipc_cleanup then
				ipc_cleanup()
			end

			M.running_git_jobs[args_table[1]] = nil
			-- run exec complete callbacks
			if exec_complete_callback then
				exec_complete_callback(code, std_out, std_err, suggestion)
				exec_complete_callback = nil
				if exec_complete_callback_return then
					return
				end
			else
				-- refresh
				vim.schedule(function()
					M.refresh_buf()
				end)
			end

			-- Show outputs.
			if #std_out > 0 then
				notify_or_open(std_out, args, code)
			else
				notify_or_open(std_err, args, code)
			end

			-- Suggestion.
			if suggestion then
				vim.schedule(function()
					util.set_cmdline(suggestion)
				end)
			end
		end,
	})

	if job_id and job_id > 0 then
		local key = util.get_unique_key(M.running_git_jobs, args_table[1])
		M.running_git_jobs[key] = job_id
	else
		util.Notify("Something went wrong.", "error", "oz_git")
	end
end

-- Define the user command
function M.oz_git_usercmd_init(config)
	M.user_config = config
	require("oz.git.user_cmd").init()
end

return M
