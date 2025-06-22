local M = {}
local util = require("oz.util")
local shell = require("oz.util.shell")
local g_util = require("oz.git.util")

local main

local function find_substring(str, substrings)
	for _, substring in pairs(substrings) do
		if str:find(substring) then
			return substring
		end
	end
	return nil
end

--- HANDLE ---
local function handle_g(opts)
	if g_util.if_in_git() then
		if opts.args and #opts.args > 0 then
			main.run_git_job(opts.args)
		else
			require("oz.git.status").GitStatus()
			vim.api.nvim_set_hl(0, "ozHelpEcho", { fg = "#606060" })
			vim.api.nvim_echo({ { "press g? to see all available keymaps.", "ozHelpEcho" } }, false, {})
		end
	elseif opts.args and opts.args:find("init") then
		main.run_git_job(opts.args)
	else
		util.Notify("You are not in a git repo. Try :Git init", "warn", "oz_git")
	end
end

local function handle_glog(opts)
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
end

-- TODO feat: instead of only one commit ability to add muliple
local function handle_gcw(opts)
	if g_util.if_in_git() then
		local arg, num, command = opts.fargs[1], nil, nil
		local last_commit = shell.shellout_str("git log -1 --format=%s")

		if last_commit:lower():match("^wip[:]?%s*") then
			num = last_commit:match("#(%d+)")
			if num then
				num = tonumber(num) + 1
			else
				num = 1
			end
			command = "git commit --amend"
		else
			num = 1
			command = "git commit"
		end

		local new_commit = ([[WIP: #%s]]):format(tostring(num))
		if arg then
			new_commit = ([[%s %s]]):format(new_commit, arg)
		else
			local staged_files = shell.shellout_str("git diff --name-only --cached")
			if staged_files ~= "" then
				local files = {}
				for file in staged_files:gmatch("([^\n]+)") do
					table.insert(files, file:match("([^/]+)$"))
				end
				new_commit = ([[%s %s]]):format(new_commit, table.concat(files, ", "))
			end
		end

		local add_cmd = opts.bang and [[git add -u && ]] or ""

		local final_cmd = ([[%s%s -m "%s"]]):format(add_cmd, command, new_commit)
		util.ShellCmd(final_cmd, function()
			util.Notify(("#%s WIP commit added."):format(tostring(num)), "info", "oz_git")
			main.refresh_buf() -- refresh status log
		end, function()
			util.Notify("Cannot create WIP commit.", "error", "oz_git")
		end)
		util.inactive_echo(final_cmd)
	end
end

local function handle_browse(opts)
	local path = vim.trim(opts.args)
	local oil_path = require("oil").get_current_dir()

	if g_util.if_in_git(oil_path) then
		if vim.bo.ft == "oil" then -- if in oil buffer
			path = oil_path
		elseif path == "" then -- if no arg is provided
			path = vim.fn.expand("%")
		end
		if path ~= "" then
			require("oz.git.browse").browse(path)
		end
	else
		util.Notify("You are not in a git repo.", "warn", "oz_git")
	end
end

local function handle_gwrite(opts)
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
				main.after_exec_complete(function()
					vim.cmd("checktime")
				end)
				vim.cmd("Git mv " .. old_name .. " " .. file_name)
			end
		end
	else
		util.Notify("You are not in a git repo.", "warn", "oz_git")
	end
end

local function handle_gread(opts)
	if g_util.if_in_git() then
		local file = opts.args
		if file == "" then
			local files = shell.shellout_tbl("git diff --name-only HEAD")
			file = find_substring(vim.fn.expand("%:p"), files)
		else
			vim.cmd("edit " .. file)
		end

		if not file then
			return
		end
		local read_content = vim.fn.systemlist({ "git", "show", ":" .. file })
		if #read_content > 0 then
			vim.api.nvim_buf_set_lines(0, 0, -1, false, read_content)
		end
	else
		util.Notify("You are not in a git repo.", "warn", "oz_git")
	end
end

local function handle_blame(args)
	if args.args ~= "" then
		require("oz.git.blame").git_blame_init(args.args)
	else
		require("oz.git.blame").git_blame_init(vim.fn.expand("%"))
	end
end

--------------

--- user_cmd init
function M.init()
	main = require("oz.git")

	-- :Git
	g_util.User_cmd({ "Git", "G" }, function(opts)
		handle_g(opts)
	end, {
		nargs = "*",
		desc = "oz_git",
		complete = function(arglead, cmdline, cursorpos)
			return require("oz.git.complete").complete(arglead, cmdline, cursorpos)
		end,
	})

	-- log
	vim.api.nvim_create_user_command("GitLog", function(opts)
		handle_glog(opts)
	end, { nargs = "*", desc = "oz_git: log" })

	-- Gr
	g_util.User_cmd({ "Gr", "Gread" }, function(opts)
		handle_gread(opts)
	end, { nargs = "?", complete = "file", desc = "oz_git: undo unstaged changes." })

	-- Gw
	g_util.User_cmd({ "Gw", "Gwrite" }, function(opts)
		handle_gwrite(opts)
	end, { nargs = "*", complete = "file", desc = "oz_git: add/stage/rename current file." })

	-- :GBrowse
	g_util.User_cmd({ "GBrowse" }, function(opts)
		handle_browse(opts)
	end, { nargs = "?", complete = "file", desc = "oz_git: browse file in the remote repo." })

	--
	g_util.User_cmd({ "GBlame" }, function(opts)
		handle_blame(opts)
	end, { nargs = "?", complete = "file", desc = "oz_git: open the blame buffer." })

	-- Gcw
	g_util.User_cmd({ "Gcw", "GitCommitWip" }, function(opts)
		handle_gcw(opts)
	end, { nargs = "?", bang = true, desc = "oz_git: create a wip commit." })
end

return M
