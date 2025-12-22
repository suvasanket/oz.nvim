local M = {}
local cache = require("oz.caching")
local shell = require("oz.util.shell")

local git_commands_cache = nil
local git_branches_cache = {}
local git_remotes_cache = nil
local git_files_cache = nil
local cache_timeout = 30
local json_name = "git_cmd_completion"

-- Filter out candidates that are already present in the command line args
local function filter_suggestions(candidates, used_args, current_arg)
	local seen_args = {}
	for _, arg in ipairs(used_args) do
		if arg ~= current_arg then
			seen_args[arg] = true
		end
	end

	local filtered = {}
	local unique_candidates = {} -- specific check to deduplicate the result list itself

	for _, cand in ipairs(candidates) do
		if not seen_args[cand] and not unique_candidates[cand] then
			unique_candidates[cand] = true
			table.insert(filtered, cand)
		end
	end
	return filtered
end

local function get_tbl(cur_arg, tbl)
	if cur_arg == "" then
		return tbl
	end
	local matches = {}
	for _, val in ipairs(tbl) do
		if val:find(cur_arg, 1, true) == 1 then
			table.insert(matches, val)
		end
	end
	return matches
end

local function get_cmdflags(command)
	local cached = cache.get_data(command, json_name)
	if cached and #cached > 0 then
		return cached
	end

	local handle = io.popen("git " .. command .. " -h 2>&1")
	if not handle then
		return {}
	end
	local output = handle:read("*a")
	handle:close()

	if not output then
		return {}
	end

	local flags = {}
	-- Clean formatting chars and extract flags (short and long)
	local clean = output:gsub("%b()", ""):gsub("%b[]", ""):gsub("%b<>", "")
	for flag in clean:gmatch("%s(%-[%w%-]+)") do
		if not vim.tbl_contains(flags, flag) then
			table.insert(flags, flag)
		end
	end

	cache.set_data(command, flags, json_name)
	return flags
end

local function get_git_commands()
	if git_commands_cache then
		return git_commands_cache
	end

	local all = cache.get_data("all_cmds", json_name) or {}
	if #all == 0 then
		local core = shell.shellout_tbl("git --help | grep -E '^   [a-z]' | awk '{print $1}'")
		local extra = shell.shellout_tbl("git help --all | grep -E '^ +[a-z]' | awk '{print $1}'")

		vim.list_extend(all, core)
		for _, cmd in ipairs(extra) do
			if not vim.tbl_contains(all, cmd) then
				table.insert(all, cmd)
			end
		end
		table.sort(all)
		cache.set_data("all_cmds", all, json_name)
	end

	git_commands_cache = all
	return all
end

local function get_git_branches(all)
	local key = all and "--all" or ""
	if git_branches_cache[key] and git_branches_cache[key].timestamp > os.time() - cache_timeout then
		return git_branches_cache[key].data
	end
	local branches = shell.shellout_tbl("git for-each-ref --format=%(refname:short) refs/heads/ refs/remotes/")
	git_branches_cache[key] = { data = branches, timestamp = os.time() }
	return branches
end

local function get_git_remotes()
	if git_remotes_cache and git_remotes_cache.timestamp > os.time() - cache_timeout then
		return git_remotes_cache.data
	end
	local remotes = shell.shellout_tbl("git remote")
	git_remotes_cache = { data = remotes, timestamp = os.time() }
	return remotes
end

local function get_git_files()
	if git_files_cache and git_files_cache.timestamp > os.time() - cache_timeout then
		return git_files_cache.data
	end
	local files = shell.shellout_tbl("git ls-files")
	local untracked = shell.shellout_tbl("git ls-files --others --exclude-standard")
	vim.list_extend(files, untracked)
	git_files_cache = { data = files, timestamp = os.time() }
	return files
end

-- Main logic: Aggregates candidates based on command context AND flags
local function specific_compl(cmd, arg, full_args)
	local candidates = {}

	-- 1. Add context-specific candidates
	if vim.tbl_contains({ "checkout", "switch", "branch", "merge", "rebase", "log", "reset" }, cmd) then
		vim.list_extend(candidates, get_git_branches(true))
	elseif vim.tbl_contains({ "add", "rm", "mv", "restore" }, cmd) then
		vim.list_extend(candidates, get_git_files())
	elseif vim.tbl_contains({ "pull", "push", "fetch" }, cmd) then
		local remotes = get_git_remotes()
		vim.list_extend(candidates, remotes)

		-- Heuristic: If a remote is already typed, suggest branches
		local has_remote = false
		for _, r in ipairs(remotes) do
			if vim.tbl_contains(full_args, r) and r ~= arg then
				has_remote = true
				break
			end
		end
		if has_remote then
			vim.list_extend(candidates, get_git_branches(true))
		end
	end

	-- 2. Always add flags for universal support
	vim.list_extend(candidates, get_cmdflags(cmd))

	-- 3. Filter already used args and match prefix
	candidates = filter_suggestions(candidates, full_args, arg)
	return get_tbl(arg, candidates)
end

function M.complete(arglead, cmdline, cursorpos)
	local args = vim.split(cmdline, "%s+")

	if #args <= 2 then
		return get_tbl(arglead, get_git_commands())
	end

	return specific_compl(args[2], arglead, args)
end

function M.invalidate_caches()
	git_commands_cache = nil
	git_branches_cache = {}
	git_remotes_cache = nil
	git_files_cache = nil
end

return M
