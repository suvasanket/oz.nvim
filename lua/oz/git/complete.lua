local M = {}
local util = require("oz.util")
local cache = require("oz.caching")

-- Cache for git commands to avoid repeated system calls
local git_commands_cache = nil
local git_branches_cache = {}
local git_remotes_cache = nil
local git_files_cache = nil
local cache_timeout = 30 -- seconds
local json_name = "git_cmd_completion"

-- Helper function to run git commands and capture output
local function capture_git_output(cmd)
	local handle = io.popen(cmd .. " 2>/dev/null")
	if not handle then
		return {}
	end

	local result = handle:read("*a")
	handle:close()

	-- Split the output by newlines and remove empty strings
	local items = {}
	for item in result:gmatch("[^\r\n]+") do
		if item ~= "" then
			table.insert(items, item)
		end
	end

	return items
end

local function get_command_flags(command)
	local cached_flags = cache.get_data(command, json_name)
	if cached_flags and #cached_flags > 0 then
		return cached_flags
	else
		local handle, output = io.popen("git " .. command .. " -h 2>&1"), {}
		if not handle then
			return output
		end

		output = handle:read("*a")
		handle:close()

		if not output then
			return {}
		end

		local flags, stripped_str = {}, output:gsub("%b()", ""):gsub("%b[]", ""):gsub("%b<>", "")
		for _, line in ipairs(vim.split(stripped_str, "\n")) do
			local comma_index = line:find(",")
			if comma_index then
				local potential_long_flag = line:sub(comma_index + 1):match("%s*(--%S+)")
				if
					potential_long_flag
					and vim.startswith(potential_long_flag, "-")
					and not potential_long_flag:find(",")
				then
					util.tbl_insert(flags, potential_long_flag)
				else
					local first_flag = line:match("%s*(-%S+)")
					if first_flag and vim.startswith(first_flag, "-") and not first_flag:find(",") then
						util.tbl_insert(flags, first_flag)
					end
				end
			else
				local first_flag, long_flag = line:match("%s*(-%S+)"), line:match("%s*(--%S+)")
				if first_flag and vim.startswith(first_flag, "-") and not first_flag:find(",") then
					util.tbl_insert(flags, first_flag)
				end
				if long_flag and vim.startswith(long_flag, "-") and not long_flag:find(",") then
					util.tbl_insert(flags, long_flag)
				end
			end
		end

		cache.set_data(command, flags, json_name)
		return flags
	end
end

-- Get all available git commands
local function get_git_commands()
	if git_commands_cache then
		return git_commands_cache
	end

	local all_cmds = cache.get_data("all_cmds", json_name) or {}

	if #all_cmds == 0 then
		local core_cmds = capture_git_output("git --help | grep -E '^   [a-z]' | awk '{print $1}'")
		local additional_cmds = capture_git_output("git help --all | grep -E '^ +[a-z]' | awk '{print $1}'")

		-- Combine and sort
		for _, cmd in ipairs(core_cmds) do
			table.insert(all_cmds, cmd)
		end

		-- Avoid duplicates
		for _, cmd in ipairs(additional_cmds) do
			if not vim.tbl_contains(all_cmds, cmd) then
				table.insert(all_cmds, cmd)
			end
		end

		table.sort(all_cmds)
		cache.set_data("all_cmds", all_cmds, json_name)
	end

	git_commands_cache = all_cmds
	return all_cmds
end

-- Get git branches
local function get_git_branches(all_branches)
	local branch_type = all_branches and "--all" or ""
	local cache_key = branch_type

	if git_branches_cache[cache_key] and git_branches_cache[cache_key].timestamp > os.time() - cache_timeout then
		return git_branches_cache[cache_key].data
	end

	local branches =
		capture_git_output("git branch " .. branch_type .. " | sed 's/^[ *]*//' | sed 's/remotes\\/origin\\///'")

	-- Clean up branch names
	for i, branch in ipairs(branches) do
		-- Remove leading markers like '*' and whitespace
		branches[i] = branch:gsub("^%s*%*?%s*", ""):gsub("^remotes/[^/]+/", "")
	end

	-- Remove duplicates
	local unique_branches = {}
	local seen = {}
	for _, branch in ipairs(branches) do
		if not seen[branch] then
			table.insert(unique_branches, branch)
			seen[branch] = true
		end
	end

	git_branches_cache[cache_key] = {
		data = unique_branches,
		timestamp = os.time(),
	}

	return unique_branches
end

-- Get git remotes
local function get_git_remotes()
	if git_remotes_cache and git_remotes_cache.timestamp > os.time() - cache_timeout then
		return git_remotes_cache.data
	end

	local remotes = capture_git_output("git remote")

	git_remotes_cache = {
		data = remotes,
		timestamp = os.time(),
	}

	return remotes
end

-- Get git files that are tracked or modified
local function get_git_files()
	if git_files_cache and git_files_cache.timestamp > os.time() - cache_timeout then
		return git_files_cache.data
	end

	local tracked = capture_git_output("git ls-files")
	local untracked = capture_git_output("git ls-files --others --exclude-standard")

	-- Combine tracked and untracked files
	local files = {}
	for _, file in ipairs(tracked) do
		table.insert(files, file)
	end

	for _, file in ipairs(untracked) do
		table.insert(files, file)
	end

	git_files_cache = {
		data = files,
		timestamp = os.time(),
	}

	return files
end

-- Get completions for git add, rm, checkout
local function get_file_completions(arg)
	local files = get_git_files()
	local matches = {}

	if arg == "" then
		return files
	end

	for _, file in ipairs(files) do
		if file:find(arg, 1, true) == 1 then
			table.insert(matches, file)
		end
	end

	return matches
end

local function get_tbl(cur_arg, tbl)
	local matches = {}
	if cur_arg == "" then
		return tbl
	end
	for _, remote in ipairs(tbl) do
		if remote:find(cur_arg, 1, true) == 1 then
			table.insert(matches, remote)
		end
	end

	return matches
end

-- Get completions for specific git commands
local function get_command_specific_completions(cmd, arg, args)
	args = { select(3, unpack(args)) }

	if arg:find("-") then -- return flags
		return get_tbl(arg, get_command_flags(cmd))
	elseif cmd == "checkout" or cmd == "switch" or cmd == "branch" then
		local branches = get_git_branches(true)

		if arg == "" then
			return get_tbl(arg, branches)
		end
	elseif cmd == "merge" or cmd == "rebase" then
		return get_command_specific_completions("checkout", arg)
	elseif cmd == "reset" or cmd == "revert" then
		return get_tbl(arg, get_command_flags(cmd))
	elseif cmd == "pull" or cmd == "push" or cmd == "fetch" then
		local remotes = get_git_remotes()
		local branches = get_git_branches(true)

		if #args == 1 then
			return get_tbl(arg, remotes)
		elseif #args == 2 then
			return get_tbl(arg, branches)
		end
	elseif cmd == "add" or cmd == "rm" or cmd == "mv" or cmd == "restore" then
		return get_file_completions(arg)
	else
		return get_command_flags(cmd)
	end
end

-- Main completion function
function M.complete(arglead, cmdline, cursorpos)
	-- Parse cmdline to see what we're completing
	local args = vim.split(cmdline, "%s+")

	-- Check if we're completing the Git command itself or its arguments
	if #args <= 2 then
		-- Completing the Git command
		local git_commands = get_git_commands()
		local matches = {}

		if arglead == "" then
			return git_commands
		end

		-- Match commands that start with arglead
		for _, cmd in ipairs(git_commands) do
			if cmd:find(arglead, 1, true) == 1 then
				table.insert(matches, cmd)
			end
		end

		return matches
	else
		-- Completing arguments for a Git subcommand
		local git_cmd = args[2]
		-- Extract the current argument we're completing
		local current_arg = arglead

		return get_command_specific_completions(git_cmd, current_arg, args)
	end
end

-- Function to invalidate caches
function M.invalidate_caches()
	git_commands_cache = nil
	git_branches_cache = {}
	git_remotes_cache = nil
	git_files_cache = nil
end

return M
