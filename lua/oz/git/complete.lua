local M = {}
local shell = require("oz.util.shell")

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

local flag_cache = {}

local function get_cmdflags(command)
	if flag_cache[command] then
		return flag_cache[command]
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

	flag_cache[command] = flags
	return flags
end

local function get_git_commands()
	-- Hardcoded list of valid subcommands we support or intend to support
	local all = {
		"add", "am", "archive", "bisect", "blame", "branch", "bundle", "checkout", "cherry-pick",
		"clean", "clone", "commit", "config", "describe", "diff", "fetch", "gc", "grep", "init",
		"log", "ls-files", "ls-remote", "ls-tree", "merge", "mv", "notes", "pull", "push",
		"rebase", "reflog", "remote", "reset", "restore", "revert", "rm", "shortlog", "show",
		"stash", "status", "submodule", "switch", "tag", "worktree",
	}

	table.sort(all)
	return all
end

local function get_git_branches()
	return shell.shellout_tbl("git for-each-ref --format=%(refname:short) refs/heads/ refs/remotes/")
end

local function get_git_remotes()
	return shell.shellout_tbl("git remote")
end

local function get_git_files()
	local files = shell.shellout_tbl("git ls-files")
	local untracked = shell.shellout_tbl("git ls-files --others --exclude-standard")
	vim.list_extend(files, untracked)
	return files
end

-- Main logic: Aggregates candidates based on command context AND flags
local function specific_compl(cmd, arg, full_args)
	local candidates = {}

	-- 1. Add context-specific candidates
	if vim.tbl_contains({ "checkout", "switch", "branch", "merge", "rebase", "log", "reset" }, cmd) then
		vim.list_extend(candidates, get_git_branches())
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
			vim.list_extend(candidates, get_git_branches())
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

return M
