--- @class oz.util.git
local M = {}

--- Check if a path is inside a Git work tree.
--- @param path? string Optional path to check.
--- @return boolean True if inside a Git work tree.
function M.if_in_git(path)
	local shell = require("oz.util.shell")
	local ok, output = shell.run_command({ "git", "rev-parse", "--is-inside-work-tree" }, path)

	if ok and output[1] then
		return output[1]:find("true") ~= nil
	end
	return false
end

--- Get the Git project root.
--- @return string|nil The Git project root path.
function M.get_project_root()
	local shell = require("oz.util.shell")
	local ok, path = shell.run_command({ "git", "rev-parse", "--show-toplevel" })
	if ok and #path ~= 0 then
		return vim.trim(table.concat(path, " "))
	end
	return nil
end

--- Get a list of Git branches.
--- @param arg? {loc?: boolean, rem?: boolean} Optional filters for local or remote branches.
--- @return string[] A list of branch names.
function M.get_branch(arg)
	local shell = require("oz.util.shell")
	local ref
	if arg and arg.loc then
		ref = "refs/heads"
	elseif arg and arg.rem then
		ref = "refs/remotes"
	else
		ref = "refs/heads refs/remotes"
	end
	return shell.shellout_tbl(string.format("git for-each-ref --format=%%(refname:short) %s", ref))
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

return M
