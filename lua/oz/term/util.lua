local M = {}

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

local read_path = {}

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

---@param pathstr string
---@param oz_cwd string
---@param cache table<string, boolean>
---@return string|nil
local function filter_path(pathstr, oz_cwd, cache)
	local function check(p)
		if M.is_readable(p, cache) then
			return p
		end
		return nil
	end

	-- 1. Try exact match first (could be absolute)
	local valid = check(pathstr)
	if valid then
		return valid
	end

	-- 2. Robust path extraction (from test.lua logic)
	-- Remove oz_cwd prefix plainly to avoid pattern matching issues with special characters
	local start, finish = pathstr:find(oz_cwd, 1, true)
	local less
	if start then
		less = pathstr:sub(finish + 1)
	else
		less = pathstr
	end

	-- Remove leading separators
	less = less:gsub("^[/\\]+", "")

	-- Find candidates for a relative path.
	local candidates = {}
	-- We look for sequences of characters commonly found in paths.
	for part in less:gmatch("[%a%d%._%-\\/]+") do
		-- A likely path contains at least one directory separator or a dot (extension/hidden file).
		if part:find("[%.%/%\\]") then
			table.insert(candidates, part)
		end
	end

	-- Try candidates from longest to shortest to catch the full path
	table.sort(candidates, function(a, b)
		return #a > #b
	end)

	for _, res in ipairs(candidates) do
		local full = oz_cwd .. "/" .. res
		valid = check(full)
		if valid then
			return valid
		end
	end

	-- Fallback: try the very last part of the string if it looks like a filename
	local last_part = less:match("([%a%d%._%-]+)$")
	if last_part then
		local full = oz_cwd .. "/" .. last_part
		valid = check(full)
		if valid then
			return valid
		end
	end

	return nil
end

--- validate_path
---@param path string
---@param cwd string
function M.find_valid_path(path, cwd)
	if M.is_readable(path, read_path) then
		return path
	end
	local v_path = filter_path(path, cwd, {})
	if v_path and M.is_readable(v_path, read_path) then
		return v_path
	else
		return nil
	end
end

---@param buf number
---@return string
function M.get_oz_cwd(buf)
	return vim.b[buf].oz_cwd or vim.fn.getcwd()
end

return M
