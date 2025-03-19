local M = {}
local util = require("oz.util")

local function parse_git_suggestion(data)
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
			extract = function(str)
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
			extract = function(str)
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
			extract = function(str)
				return "pull --rebase"
			end,
		},
		-- Merge conflict resolution
		{
			trigger = "fix conflicts",
			extract = function(str)
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
			extract = function(str)
				return "push --force"
			end,
		},
		-- Fetch first suggestion
		{
			trigger = "have you pulled",
			extract = function(str)
				return "pull"
			end,
		},
		-- Amend suggestions
		{
			trigger = "forgot to add some files",
			extract = function(str)
				vim.notify("put your files.")
				return "add [files] && commit --amend"
			end,
		},
		-- Interactive rebase suggestion
		{
			trigger = "use interactive rebase",
			extract = function(str)
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
	local buf = vim.api.nvim_create_buf(false, true)

	vim.cmd("belowright split")
	vim.cmd("resize 7")

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "number", false)
	vim.api.nvim_buf_set_option(buf, "relativenumber", false)
	vim.api.nvim_buf_set_option(buf, "ft", "git") -- TODO set env shell.

	return buf
end

local function run_git_command(args)
	if not args or #args == 0 then
		vim.notify("Please provide arguments for the Git command.")
		return
	end
	local args_table = vim.split(args, "%s+")

	---@diagnostic disable-next-line: deprecated
	local job_id = vim.fn.jobstart({ "git", unpack(args_table) }, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data, _)
			-- TODO: different on push, pull, clone
			if data[1] ~= "" then
				open_output_split(data)
			end
		end,
		on_stderr = function(_, data, _)
			local suggestion, title = parse_git_suggestion(data)
			if suggestion then
				util.Notify("Error: " .. data[1], "warn", "oz_git")
				vim.api.nvim_feedkeys(":Git " .. suggestion, "n", false)
			else
				if data[1] ~= "" then
					open_output_split(data)
				end
			end
		end,
	})

	if job_id <= 0 then
		print("Failed to start job")
	end
end

-- Define the user command
vim.api.nvim_create_user_command(
	"Git",
	function(opts)
		run_git_command(opts.args)
	end,
	{ nargs = "+" } -- Options, e.g., { nargs = '+' } for variable number of arguments
)

return M
