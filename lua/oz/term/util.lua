local M = {}

M.EFM_PATTERNS = {
	"%f:%l:%c: %m",
	"%f:%l: %m",
	"%f:%l:%m",
	"%f(%l,%c): %m",
	"%f(%l): %m",
	"%f:%l:%c",
	"%f:%l",
}

M.URL_PATTERN = [[https\?://[a-zA-Z0-9_%-.\?.:/+=&]\+]]

-- More restrictive path-like pattern to reduce false positives and improve performance
-- Requires at least 3 characters for the path part
M.PATH_PATTERN = [[\v[a-zA-Z0-9./\_%@~-]{3,}%([:()]\d+)*]]

---@param path string
---@param cache table<string, boolean>
---@return boolean
function M.is_readable(path, cache)
	if cache[path] ~= nil then
		return cache[path]
	end
	local res = vim.fn.filereadable(path) ~= 0 or vim.fn.isdirectory(path) ~= 0
	cache[path] = res
	return res
end

---@param buf number
---@return string
function M.get_oz_cwd(buf)
	return vim.b[buf].oz_cwd or vim.fn.getcwd()
end

return M
