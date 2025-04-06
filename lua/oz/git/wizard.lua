local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")

M.on_conflict_resolution = false
M.on_conflict_resolution_complete = nil

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
				return arg_tbl[1] .. "| " .. table.concat(arg_tbl, " ", 2)
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
				vim.notify_once("Chief, please commit or stash before we proceed.")
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
				vim.notify_once("We've got your back, Chief.")
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
				return "Git " .. suggestion
			end
		end
	end
end

-- commit push wizard --
function M.push_wizard()
	local remote = util.ShellOutput("git config --get remote.origin.url")
	local no_unpushed = util.ShellOutput("git rev-list --count @{u}..HEAD")
	if remote ~= "" then
		vim.notify(
			"[󱦲" .. no_unpushed .. "] press 'P' to push any other key to dismiss.",
			vim.log.levels.INFO,
			{ title = "oz_git", timeout = 3000 }
		)
		local char = vim.fn.getchar()
		char = vim.fn.nr2char(char)
		if char == "P" then
			vim.cmd("Git push")
		else
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(char, true, false, true), "n", false)
			pcall(require("notify").dismiss)
			pcall(require("snacks.notifier").hide)
			pcall(require("mini.notify").clear)
		end
	end
end

-- conflict wizard --
local conflicted_files = {}
function M.start_conflict_resolution()
	conflicted_files = util.ShellOutputList([[git status --short | awk '/^[ADU][ADU] / {print $2}']])
	if #conflicted_files > 0 then
		vim.fn.setqflist({}, " ", {
			lines = conflicted_files,
			efm = "%f",
			title = "OzGitMergeConflictFiles",
		})

		if #vim.fn.getqflist() == 1 then
			vim.cmd("cfirst")
		elseif #vim.fn.getqflist() > 0 then
			vim.cmd("cw")
			vim.cmd("cfirst")
		end
		-- set keymaps
		g_util.temp_remap("n", "]x", function()
			local patterns = { "^<<<<<<<", "^=====", "^>>>>>>" }
			for _, pattern in ipairs(patterns) do
				local result = vim.fn.search(pattern, "W")
				if result ~= 0 then
					return
				end
			end
			print("next")
		end, { remap = false, silent = true })

		g_util.temp_remap("n", "[x", function()
			local patterns = { "^>>>>>>", "^=====", "^<<<<<<<" }
			for _, pattern in ipairs(patterns) do
				local result = vim.fn.search(pattern, "Wb")
				if result ~= 0 then
					return
				end
			end
			print("prev")
		end, { remap = false, silent = true })

		M.on_conflict_resolution = true
	else
		util.Notify("ShellError: git status --short | awk '/^[ADU][ADU] / {print $2}", "error", "oz_git")
	end
end

function M.complete_conflict_resolution()
	if #conflicted_files == 0 then
		util.Notify("ShellError: git status --short | awk '/^[ADU][ADU] / {print $2}", "error", "oz_git")
		return
	end
	g_util.restore_mapping("n", "[x")
	g_util.restore_mapping("n", "]x")

	-- util.clear_qflist("OzGitMergeConflictFiles")
	vim.cmd("cclose")

	for _, file in ipairs(conflicted_files) do
		local lines = vim.fn.readfile(file)
		local new_lines = {}
		for _, line in ipairs(lines) do
			if not (line:match("^<<<<<<<") or line:match("^=======") or line:match("^>>>>>>>")) then
				table.insert(new_lines, line)
			end
		end
		local bufnr = vim.fn.bufnr(file)
		if bufnr ~= -1 then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, new_lines)
			vim.api.nvim_buf_set_option(bufnr, "modified", true)
		end
	end
	M.on_conflict_resolution_complete = true
end

return M
