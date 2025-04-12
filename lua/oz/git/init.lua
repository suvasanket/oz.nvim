local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local wizard = require("oz.git.wizard")
local oz_git_win = require("oz.git.oz_git_win")

M.user_config = nil
M.running_git_jobs = {}

-- helper: notify or open in window
local function notify_or_open(output, args, type)
	if #output == 0 then
		return
	end
	local notfy_level = type == "std_out" and "info" or "error"
	if #output <= 2 then
		util.Notify(table.concat(output, "\n"), notfy_level, "oz_git")
	else
		oz_git_win.open_oz_git_win(output, args, type)
	end
end

-- CMD parser
local function different_cmd_runner(args_table, args_str)
	local cmd = args_table[1]

	local editor_req_cmds =
		{ "commit", "commit --amend", "tag -a", "rebase -i", "merge --no-commit", "notes add", "filter-branch" }
	if util.str_in_tbl(args_str, editor_req_cmds) then
		if vim.fn.executable("nvr") ~= 1 then
			util.Notify("neovim-remote not found, install to use editor required commands.")
			return true
		end
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

	local remote_cmds = { "push", "pull", "fetch", "clone", "request-pull", "svn" }
	local interactive_cmd = { "add -p", "reset -p", "commit -p", "git checkout -p" }

	-- all the conditional commands here.
	if cmd == "status" then
		local oz_git_buf = require("oz.git.oz_git_win").oz_git_buf
		if oz_git_buf then
			vim.api.nvim_buf_delete(oz_git_buf, { force = true })
		end
		require("oz.git.status").GitStatus()
		return true
	elseif cmd == "commit" and #args_table == 1 then -- check if non staged commiting.
		local changed = util.ShellOutputList("git diff --name-only --cached")
		if #changed < 1 then
			util.Notify("Nothing to commit.", "error", "oz_git")
			return true
		end
	elseif util.str_in_tbl(args_str, interactive_cmd) then
		g_util.run_term_cmd({
			cmd = "git " .. util.str_in_tbl(args_str, interactive_cmd),
			on_exit_callback = function()
				util.Notify("Interactive hunk selection ended.", nil, "oz_git")
			end,
		})
	elseif vim.tbl_contains(args_table, "--help") then -- man
		vim.cmd("Man git-" .. cmd)
		return true
	elseif vim.tbl_contains(remote_cmds, cmd) then -- remote related
		if M.user_config and M.user_config.remote_operation_exec_method == "background" then -- user config
			local command = table.remove(args_table, 1)

			require("oz.git.progress_cmd").run_git_with_progress(command, args_table, function(lines)
				oz_git_win.open_oz_git_win(lines, args_str, "stderr")
				-- git suggestion
				local suggestion = wizard.get_git_suggestions(lines, args_table)
				if suggestion then
					g_util.set_cmdline(suggestion)
				end
			end)
		elseif M.user_config and M.user_config.remote_operation_exec_method == "term" then
			vim.cmd("hor term git " .. table.concat(args_table, " "))
			vim.api.nvim_buf_set_option(0, "ft", oz_git_win.oz_git_ft() and "oz_git" or "git")
			vim.cmd("resize 9")
			vim.api.nvim_buf_set_name(0, "")
			vim.cmd.wincmd("p")
		end
		return true
	end
end

-- callback to run after :Git cmd complete
local exec_complete_callback = nil
local exec_complete_callback_return = false
function M.after_exec_complete(callback, ret)
	if callback then
		exec_complete_callback = callback
	end
	exec_complete_callback_return = ret or false
end

-- ENV --
local plugin_diff_tool_name = "nvr_plugin_diff"
local plugin_merge_tool_name = "nvr_plugin_merge"

local nvr_diff_cmd = [[nvr -s -d "$LOCAL" "$REMOTE"]]
local nvr_merge_cmd = [[nvr -s -d $LOCAL $BASE $REMOTE $MERGED -c 'wincmd J | wincmd =']]

local job_env = {
	GIT_EDITOR = "nvr -cc split --remote-wait",
	GIT_SEQUENCE_EDITOR = "nvr -cc split --remote-wait",

	GIT_CONFIG_COUNT = "4",

	GIT_CONFIG_KEY_0 = "diff.tool",
	GIT_CONFIG_VALUE_0 = plugin_diff_tool_name,

	GIT_CONFIG_KEY_1 = "difftool." .. plugin_diff_tool_name .. ".cmd",
	GIT_CONFIG_VALUE_1 = nvr_diff_cmd,

	GIT_CONFIG_KEY_2 = "merge.tool",
	GIT_CONFIG_VALUE_2 = plugin_merge_tool_name,

	GIT_CONFIG_KEY_3 = "mergetool." .. plugin_merge_tool_name .. ".cmd",
	GIT_CONFIG_VALUE_3 = nvr_merge_cmd,

	GIT_CONFIG_KEY_4 = "mergetool." .. plugin_merge_tool_name .. ".trustExitCode",
	GIT_CONFIG_VALUE_4 = "false",
}

-- refresh any required buffers.
function M.refresh_buf()
	local status_win = require("oz.git.status").status_win
	local log_win = require("oz.git.git_log").log_win

	if status_win and vim.api.nvim_win_is_valid(status_win) then
		require("oz.git.status").refresh_status_buf(true)
	elseif log_win and vim.api.nvim_win_is_valid(log_win) then
		require("oz.git.git_log").refresh_commit_log(true)
	end
end

-- remove any running jobs.
function M.cleanup_git_jobs(args)
	if args then
		if args.job_id then
			vim.fn.jobstop(args.job_id)
		end
		if args.cmd then
			for key, job_id in pairs(M.running_git_jobs) do
				if key:match("^" .. args.cmd .. "%d*$") then
					vim.fn.jobstop(job_id)
                    -- vim.fn.jobsend(job_id, ":wq\n")  -- sends a :wq command
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

-- Run Git cmd.
function M.run_git_job(args)
	args = g_util.expand_expressions(args)
	local args_table = g_util.parse_args(args)
	local suggestion = nil
	local std_out = {}
	local std_err = {}

	if different_cmd_runner(args_table, args) then
		return
	end

	local job_id = vim.fn.jobstart({ "git", unpack(args_table) }, {
		stdout_buffered = true,
		stderr_buffered = true,
		env = job_env,
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
			local type = code == 0 and "std_out" or "std_err"
			if #std_out > 0 then
				notify_or_open(std_out, args, type)
			else
				notify_or_open(std_err, args, type)
			end

			-- Suggestion.
			if suggestion then
				vim.schedule(function()
					g_util.set_cmdline(suggestion)
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
	-- :Git
	g_util.User_cmd({ "Git", "G" }, function(opts)
		if g_util.if_in_git() then
			if opts.args and #opts.args > 0 then
				M.run_git_job(opts.args)
			else
				require("oz.git.status").GitStatus()
				vim.api.nvim_set_hl(0, "ozHelpEcho", { fg = "#606060" })
				vim.api.nvim_echo({ { "press g? to see all available keymaps.", "ozHelpEcho" } }, false, {})
			end
		elseif opts.args and opts.args:find("init") then
			M.run_git_job(opts.args)
		else
			util.Notify("You are not in a git repo. Try :Git init", "warn", "oz_git")
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
			if opts.args ~= "" then
				local args_table = vim.split(opts.args, "%s+")
				require("oz.git.git_log").commit_log({ level = 1 }, args_table)
			else
				require("oz.git.git_log").commit_log()
			end
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", desc = "oz_git log" })

	-- Gr
	vim.api.nvim_create_user_command("Gr", function()
		if g_util.if_in_git() then
			M.after_exec_complete(function()
				pcall(vim.cmd, "edit")
			end)
			vim.cmd("Git checkout -- %")
			vim.api.nvim_echo({ { ":Git " }, { "checkout -- %", "ModeMsg" } }, false, {})
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", desc = "Git read" })

	-- Gw
	vim.api.nvim_create_user_command("Gw", function(opts)
		local file_name = vim.trim(opts.args)
		if g_util.if_in_git() then
			if file_name == "" then
				local ok = pcall(vim.cmd, "w")
				if ok then
					vim.cmd("Git add %")
				end
			else
				local old_name = vim.fn.expand("%")
				local ok = pcall(vim.cmd, "w", file_name)
				if ok then
					M.after_exec_complete(function(code)
						if code == 0 then
							vim.cmd("edit " .. file_name)
						end
					end)
					vim.cmd("Git mv " .. old_name .. " " .. file_name)
				end
			end
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", desc = "Git write" })
end

return M
