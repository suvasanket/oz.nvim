local M = {}
local util = require("oz.util")

M.on_conflict_resolution = false
M.on_conflict_resolution_complete = nil

local shellout_str = util.shellout_str

--- Get suggestion if error in user-cmd
---@param data table
---@param arg_tbl table
---@return string|nil
function M.get_git_suggestions(data, arg_tbl)
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
			trigger = "Did you mean",
			extract = function(str)
				local match = str:match("Did you mean%s+([^%s]+)")
				if match then
					return match:gsub("^git%s+", "")
				end
				return nil
			end,
		},
		{
			trigger = "The most similar commands are",
			extract = function()
				if #arg_tbl == 1 then
					return arg_tbl[1]
				end
				return string.format("%s| %s", arg_tbl[1], table.concat(arg_tbl, " ", 2))
			end,
		},
		{
			trigger = "The most similar command",
			extract = function(str)
				local match = str:match("The most similar command is%s*['\"]?([^'\"]+)['\"]?")
				if #arg_tbl == 1 then
					return match
				else
					return match .. "| " .. table.concat(arg_tbl, " ", 2)
				end
			end,
		},
		-- User identity setup
		{
			trigger = "Please tell me who you are",
			extract = function()
				local uname = shellout_str("whoami")
				return "config --global user.email | && config --global user.name " .. uname
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
				vim.notify_once("Please commit or stash before we proceed.")
				return "stash"
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
				vim.notify_once("We are in a conflict, press enter for details.")
				return "Git"
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
				vim.notify_once("You should checkout to a working branch.")
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
				vim.notify("Chief, you should pull first.")
				return "pull"
			end,
		},
		-- Amend suggestions
		{
			trigger = "forgot to add some files",
			extract = function()
				vim.notify("Chief, it seems you forgot to add some files.")
				return "add | && commit --amend"
			end,
		},
		-- Config suggestions
		{
			trigger = "set your configuration",
			extract = function(str)
				local config_key = str:match("git config ([^%s]+)")
				if config_key then
					return "config " .. config_key
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
							vim.notify_once("Chief we got some suggestions, press enter to proceed.")
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
				suggestion = suggestion:sub(1, 3) == "Git" and suggestion or "Git " .. suggestion
				return suggestion
			end
		end
	end
end

return M
