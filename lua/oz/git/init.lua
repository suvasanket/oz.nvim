local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")

local oz_git_buf = nil
local oz_git_win = nil

local function parse_git_suggestion(data, arg_cmd)
	local filtered_data = {}
	for _, line in ipairs(data) do
		if line and line ~= "" then
			table.insert(filtered_data, line)
		end
	end

	local output_str = table.concat(filtered_data, "\n")

	local patterns = {
		-- Command similarity suggestions
		{
			trigger = "The most similar command",
			extract = function(str)
				local match = str:match("The most similar command is%s*['\"]?([^'\"]+)['\"]?")
				return match and vim.trim(match) or nil
			end,
		},
		{
			trigger = "The most similar commands are",
			extract = function()
				return arg_cmd
			end,
		},
		{
			trigger = "Did you mean",
			extract = function(str)
				local match = str:match("Did you mean%s+([^%s]+)")
				if match then
					return match:gsub("^git%s+", "")
				end
				return nil
			end,
		},
		-- User identity setup
		{
			trigger = "Please tell me who you are",
			extract = function()
				return "config --global user.email YOUR_EMAIL && config --global user.name YOUR_NAME"
			end,
		},
		-- Upstream tracking suggestions
		{
			trigger = "set the upstream",
			extract = function(str)
				local remote, branch = str:match("%-%-set%-upstream%-to=([^%s]+)%s+([^%s]+)")
				if remote and branch then
					return "branch --set-upstream-to=" .. remote .. " " .. branch
				end

				remote, branch = str:match("%-%-set%-upstream%s+([^%s]+)%s+([^%s]+)")
				if remote and branch then
					return "push --set-upstream " .. remote .. " " .. branch
				end

				return nil
			end,
		},
		-- Working tree state suggestions
		{
			trigger = "Please commit or stash",
			extract = function()
				return "stash"
			end,
		},
		-- Remote repository setup
		{
			trigger = "configure a remote repository",
			extract = function(str)
				local match = str:match("git remote add [^%s]+ [^%s]+")
				if match then
					return match:gsub("^git%s+", "")
				end
				return "remote add origin YOUR_REPOSITORY_URL"
			end,
		},
		-- Branch checkout suggestions
		{
			trigger = "to create a new branch",
			extract = function(str)
				local branch = str:match("git checkout %-%-track [^%s]+/([^%s]+)")
				if branch then
					return "checkout -b " .. branch
				end
				return nil
			end,
		},
		-- Pull with rebase suggestion
		{
			trigger = "pull with rebase",
			extract = function()
				return "pull --rebase"
			end,
		},
		-- Merge conflict resolution
		{
			trigger = "fix conflicts",
			extract = function()
				return "status # Then fix conflicts and run 'add' followed by 'commit'"
			end,
		},
		-- Detached HEAD suggestions
		{
			trigger = "detached HEAD state",
			extract = function(str)
				local branch = str:match("git checkout %-%-track [^%s]+/([^%s]+)")
				if branch then
					return "checkout -b " .. branch
				end
				vim.notify("followed by new-branch name.")
				return "checkout -b "
			end,
		},
		-- Force push suggestion
		{
			trigger = "force the update",
			extract = function()
				return "push --force"
			end,
		},
		-- Fetch first suggestion
		{
			trigger = "have you pulled",
			extract = function()
				return "pull"
			end,
		},
		-- Amend suggestions
		{
			trigger = "forgot to add some files",
			extract = function()
				vim.notify("put your files.")
				return "add [files] && commit --amend"
			end,
		},
		-- Interactive rebase suggestion
		{
			trigger = "use interactive rebase",
			extract = function()
				vim.notify("followed by the number of commits.")
				return "rebase -i HEAD~"
			end,
		},
		-- Config suggestions
		{
			trigger = "set your configuration",
			extract = function(str)
				local config_key = str:match("git config ([^%s]+)")
				if config_key then
					return "config " .. config_key .. " VALUE"
				end
				return nil
			end,
		},
		-- Generic suggestions (fallback for other patterns)
		{
			trigger = "hint:",
			extract = function(str)
				local hint = str:match("hint:%s+([^\n]+)")
				if hint then
					local cmd = hint:match("^git%s+([%w%s%-]+)")
					if cmd then
						return vim.trim(cmd)
					end
				end
				return nil
			end,
		},
		{
			trigger = "fatal:",
			extract = function(str)
				-- Look for a git command suggestion after fatal
				local lines = vim.split(str, "\n")
				local find_suggestion = false

				for _, line in ipairs(lines) do
					if find_suggestion then
						local cmd = line:match("^%s*git%s+([%w%s%-]+)")
						if cmd then
							return vim.trim(cmd)
						end
					end

					if line:match("fatal:") then
						find_suggestion = true
					end
				end
				return nil
			end,
		},
	}

	-- Check for each pattern in the output
	for _, pattern in ipairs(patterns) do
		if output_str:find(pattern.trigger) then
			local suggestion = pattern.extract(output_str)
			if suggestion then
				return suggestion, pattern.trigger
			end
		end
	end

	return nil
end

local function open_output_split(lines)
	local height = math.min(math.max(#lines, 7), 15)

	if oz_git_buf == nil or not vim.api.nvim_win_is_valid(oz_git_win) then
		oz_git_buf = vim.api.nvim_create_buf(false, true)

		vim.cmd("botright " .. height .. "split")
		vim.cmd("resize " .. height)

		oz_git_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(oz_git_win, oz_git_buf)

		vim.api.nvim_buf_set_lines(oz_git_buf, 0, -1, false, lines)

		-- vim.api.nvim_buf_set_name(oz_git_buf, "**oz_git**")
		vim.api.nvim_buf_set_option(oz_git_buf, "ft", "oz_git")

		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = oz_git_buf,
			callback = function()
				oz_git_buf = nil
				oz_git_win = nil
			end,
		})
	else
		vim.api.nvim_set_current_win(oz_git_win)
		vim.cmd("resize " .. height)
		vim.api.nvim_buf_set_option(oz_git_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(oz_git_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(oz_git_buf, "modifiable", false)
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
			suggestion = parse_git_suggestion(data, cmd)
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line and line ~= "" then
						table.insert(std_err, line)
					end
				end
			end
			suggestion = parse_git_suggestion(data, cmd)
		end,
		on_exit = function()
			if is_remote and #std_err == 0 then -- remote dependant
				util.Notify(complete, nil, "oz_git")
				-- util.Notify("press enter to see status.", nil, "oz_git")
				-- local char = vim.fn.getchar()
				-- char = vim.fn.nr2char(char)
				-- if char == "\r" or char == "\n" then
				-- 	vim.cmd("Git status")
				-- end
			elseif #std_out ~= 0 then
				open_output_split(std_out)
			elseif #std_err ~= 0 then
				open_output_split(std_err)
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
vim.api.nvim_create_user_command("Git", function(opts)
	-- oz_git ft..
	require("oz.git.oz_git_ft").oz_git_hl()
	-- git cmd
	run_git_command(opts.args)
end, { nargs = "+" })

return M
