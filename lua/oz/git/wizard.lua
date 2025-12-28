local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local shell = require("oz.util.shell")

M.on_conflict_resolution = false
M.on_conflict_resolution_complete = nil

local shellout_str = shell.shellout_str

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

-- commit push wizard --
function M.push_wizard()
	local remote = shellout_str("git config --get remote.origin.url")
	local no_unpushed = shellout_str("git rev-list --count @{u}..HEAD")
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
	local res = shell.shellout_tbl("git status --short")
	for _, line in ipairs(res) do
		if line:match("^.[ADU] ") then
			table.insert(conflicted_files, line:sub(3))
		end
	end

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
		end, { remap = false, silent = true })

		g_util.temp_remap("n", "[x", function()
			local patterns = { "^>>>>>>", "^=====", "^<<<<<<<" }
			for _, pattern in ipairs(patterns) do
				local result = vim.fn.search(pattern, "Wb")
				if result ~= 0 then
					return
				end
			end
		end, { remap = false, silent = true })

		M.on_conflict_resolution = true
	end
end

function M.rebase_buf_mappigs(buf)
	local map = util.Map

	-- Helper fucntion --
	local function set_prefix(str)
		if vim.api.nvim_get_mode().mode == "n" then
			local line = vim.api.nvim_get_current_line()
			line = line:gsub("^%w.*-[c|C]", "pick"):gsub("^%w+", str)
			vim.api.nvim_set_current_line(line)
		else
			local start_line = vim.fn.line("v")
			local end_line = vim.fn.line(".")
			local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
			vim.api.nvim_input("<Esc>")
			for i, line in ipairs(lines) do
				lines[i] = line:gsub("^%w+", str)
			end
			vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, lines)
		end
		vim.notify_once("After done press 'c' or '<cr>' to continue.")
	end

	local function insert_with(str)
		local current_line = vim.api.nvim_get_current_line()
		if vim.deep_equal(current_line:match("^%w+"), str) then
			return "A"
		else
			return "o" .. str .. " "
		end
	end

	-- Mappings --
	map({ "n", "x" }, "r", function()
		set_prefix("reword")
	end, { buffer = buf, desc = "reword" })

	map({ "n", "x" }, "d", function()
		local current_line = vim.api.nvim_get_current_line()
		if g_util.str_contains_hash(current_line) then
			set_prefix("drop")
		else
			local word = current_line:match("^%w+") or ""
			local ans = util.prompt("delete " .. word .. "?", "&delete\n&no", 1)
			if ans == 1 then
				vim.api.nvim_del_current_line()
			end
		end
	end, { nowait = true, buffer = buf, desc = "drop" })

	map({ "n", "x" }, "s", function()
		set_prefix("squash")
	end, { nowait = true, buffer = buf, desc = "squash" })

	map({ "n", "x" }, "f", function()
		local cur_line = vim.api.nvim_get_current_line()
		if vim.startswith(cur_line, "fixup -C") then
			set_prefix("fixup")
		elseif vim.startswith(cur_line, "fixup -c") then
			set_prefix("fixup -C")
		elseif vim.startswith(cur_line, "fixup") then
			set_prefix("fixup -c")
		else
			set_prefix("fixup")
		end
	end, { nowait = true, buffer = buf, desc = "fixup" })

	map({ "n", "x" }, "p", function()
		set_prefix("pick")
	end, { buffer = buf, desc = "pick" })

	map({ "n", "x" }, "e", function()
		set_prefix("edit")
	end, { buffer = buf, desc = "edit" })

	map("n", "l", function()
		return insert_with("label")
	end, { expr = true, buffer = buf, desc = "label" })

	map("n", "x", function()
		return insert_with("exec")
	end, { expr = true, buffer = buf, desc = "exec" })

	map("n", "t", function()
		return insert_with("reset")
	end, { expr = true, buffer = buf, desc = "reset" })

	map("n", "m", function()
		return insert_with("merge")
	end, { expr = true, buffer = buf, desc = "merge" })

	map("n", "u", function()
		return insert_with("update-ref")
	end, { expr = true, buffer = buf, desc = "update-ref" })

	map("n", { "<cr>", "c" }, function()
		local ans = util.prompt("continue with saving the buffer?", "&confirm\n&no", 1)
		if ans == 1 then
			vim.cmd("silent wq")
		end
	end, { buffer = buf, desc = "continue rebase buffer" })

	map("n", "q", "<cmd>q<cr>", { buffer = buf, desc = "quit rebase buffer" })
end

return M
