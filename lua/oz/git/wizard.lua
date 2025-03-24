local M = {}
local util = require("oz.util")

function M.parse_git_suggestion(data, arg_tbl)
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
			trigger = "The most similar command is",
			extract = function(str)
				local match = str:match("The most similar command is%s*['\"]?([^'\"]+)['\"]?")
				if #arg_tbl == 1 then
					return match
				else
					return match .. "| " .. table.concat(arg_tbl, " ", 2)
				end
			end,
		},
		{
			trigger = "The most similar commands are",
			extract = function()
				if #arg_tbl == 1 then
					return arg_tbl[1]
				end
				return arg_tbl[1] .. "| " .. table.concat(arg_tbl, " ", 2)
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
				local uname = util.ShellOutput("whoami")
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
				return "remote add origin "
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
				vim.notify("Then fix conflicts and run 'add' followed by 'commit'")
				return "status"
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
				return "add | && commit --amend"
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

function M.commit_wizard()
	local remote = util.ShellOutput("git config --get remote.origin.url")
	local no_unpushed = util.ShellOutput("git rev-list --count @{u}..HEAD")
	if remote ~= "" then
		vim.api.nvim_echo({
			{ "[󱦲" .. no_unpushed .. "]", "ModeMsg" },
			{ " press " },
			{ "'P'", "ModeMsg" },
			{ " to push or any other key to dismiss:" },
		}, false, {})
		local char = vim.fn.getchar()
		char = vim.fn.nr2char(char)
		if char == "P" then
			vim.cmd("Git push")
		end
		vim.api.nvim_echo({ { "" } }, false, {})
	end
end

return M
