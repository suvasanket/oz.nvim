--- @class oz.term.util
local M = {}
local util = require("oz.util")

M.EFM_PATTERNS = {
	"%f:%l:%c: %m",
	"%f:%l:%c",
	"%f:%l: %m",
	"%f(%l,%c): %m",
	"%f(%l): %m",
	"%f:%l",
	"%f:%l:%m",
}

M.URL_PATTERN = [[https\?://[a-zA-Z0-9_%-.\?.:/+=&]\+]]

-- More restrictive path-like pattern to reduce false positives and improve performance
M.PATH_PATTERN = [[\v[a-zA-Z0-9./\_%@~-]{2,}%([:()]\d+)*]]

--- Check if a path is readable.
--- @param path string
--- @param cache table<string, boolean>
--- @return boolean
function M.is_readable(path, cache)
	return util.is_readable(path, cache)
end

--- Find a valid readable path from a string and CWD.
--- @param path string
--- @param cwd string
--- @return string|nil
function M.find_valid_path(path, cwd)
	return util.find_valid_path(path, cwd)
end

--- Get the current working directory for a given buffer.
--- @param buf integer
--- @return string
function M.get_oz_cwd(buf)
	return vim.b[buf].oz_cwd or vim.fn.getcwd()
end

return M
