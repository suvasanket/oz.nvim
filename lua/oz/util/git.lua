--- @class oz.util.git
local M = {}
local util = require("oz.util")

--- Check if a path is inside a Git work tree.
--- @param path? string Optional path to check.
--- @return boolean True if inside a Git work tree.
function M.if_in_git(path)
	local ok, output = util.run_command({ "git", "rev-parse", "--is-inside-work-tree" }, path)

	if ok and output[1] then
		return output[1]:find("true") ~= nil
	end
	return false
end

--- Get the Git project root.
--- @return string|nil The Git project root path.
function M.get_project_root()
	local ok, path = util.run_command({ "git", "rev-parse", "--show-toplevel" })
	if ok and #path ~= 0 then
		return vim.trim(table.concat(path, " "))
	end
	return nil
end

--- Get a list of Git branches.
--- @param arg? {loc?: boolean, rem?: boolean} Optional filters for local or remote branches.
--- @return string[] A list of branch names.
function M.get_branch(arg)
	local ref
	if arg and arg.loc then
		ref = "refs/heads"
	elseif arg and arg.rem then
		ref = "refs/remotes"
	else
		ref = "refs/heads refs/remotes"
	end
	return util.shellout_tbl(string.format("git for-each-ref --format=%%(refname:short) %s", ref))
end

--- Check if a string contains something that looks like a Git hash.
--- @param text string The string to check.
--- @return boolean True if it contains a hash.
function M.str_contains_hash(text)
	if type(text) ~= "string" then
		return false
	end

	for hex_sequence in text:gmatch("(%x+)") do
		local len = #hex_sequence
		if (len >= 7 and len <= 12) or len == 40 or len == 64 then
			return true
		end
	end
	return false
end

--- Get the current state of the Git repository.
--- @param cwd? string The working directory.
--- @return {operation: string, hash: string|nil} | nil
function M.get_git_state(cwd)
	local git_dir = util.shellout_str("git rev-parse --git-dir", cwd)
	if not git_dir or git_dir == "" then return nil end

	local paths = {
		{ path = git_dir .. "/BISECT_LOG", op = "bisect", head = nil },
		{ path = git_dir .. "/CHERRY_PICK_HEAD", op = "cherry-pick", head = "CHERRY_PICK_HEAD" },
		{ path = git_dir .. "/MERGE_HEAD", op = "merge", head = "MERGE_HEAD" },
		{ path = git_dir .. "/REBASE_HEAD", op = "rebase", head = "REBASE_HEAD" },
		{ path = git_dir .. "/rebase-merge", op = "rebase", head = nil },
		{ path = git_dir .. "/rebase-apply", op = "rebase", head = nil },
	}

	for _, p in ipairs(paths) do
		if vim.fn.filereadable(p.path) == 1 or vim.fn.isdirectory(p.path) == 1 then
			local hash = p.head and util.shellout_str("git rev-parse --short " .. p.head, cwd) or nil
			return { operation = p.op, hash = hash }
		end
	end
	return nil
end

return M
