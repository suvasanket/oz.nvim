--- @class oz.util.fs
local M = {}

--- Check if a path is readable (file or directory).
--- @param path string The path to check.
--- @param cache? table<string, boolean> Optional cache table to store results.
--- @return boolean True if readable.
function M.is_readable(path, cache)
	if cache and cache[path] ~= nil then
		return cache[path]
	end
	local res = vim.fn.filereadable(path) ~= 0 or vim.fn.isdirectory(path) ~= 0
	if cache then
		cache[path] = res
	end
	return res
end

--- Find the project root directory based on standard markers or workspace folders.
--- @param markers? string[] Optional list of custom markers to search for.
--- @param path_or_bufnr? string|integer Optional starting path or buffer number. Defaults to 0 (current buffer).
--- @return string|nil The project root path, or nil if not found.
function M.GetProjectRoot(markers, path_or_bufnr)
	if markers then
		return vim.fs.root(path_or_bufnr or 0, markers) or nil
	end

	local patterns = { ".git", "Makefile", "Cargo.toml", "go.mod", "pom.xml", "build.gradle" }
	local root_fpattern = vim.fs.root(path_or_bufnr or 0, patterns)
	local workspace = vim.lsp.buf.list_workspace_folders()

	if root_fpattern then
		return root_fpattern
	elseif workspace and #workspace > 0 then
		return workspace[#workspace]
	else
		return nil
	end
end

--- Filter and validate a path string against a CWD.
--- @param pathstr string The path string to validate.
--- @param oz_cwd string The current working directory to check against.
--- @param cache table<string, boolean> Cache table for readability checks.
--- @return string|nil The validated path, or nil if not found.
local function filter_path(pathstr, oz_cwd, cache)
	local function check(p)
		if M.is_readable(p, cache) then
			return p
		end
		return nil
	end

	local valid = check(pathstr)
	if valid then
		return valid
	end

	local start, finish = pathstr:find(oz_cwd, 1, true)
	local less
	if start then
		less = pathstr:sub(finish + 1)
	else
		less = pathstr
	end

	less = less:gsub("^[/\\]+", "")

	local candidates = {}
	for part in less:gmatch("[%a%d%._%-\\/]+") do
		if part:find("[%.%/%\\]") then
			table.insert(candidates, part)
		end
	end

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

--- Find a valid readable path from a string and CWD.
--- @param path string The path string.
--- @param cwd string The working directory.
--- @return string|nil The valid path or nil.
function M.find_valid_path(path, cwd)
	local read_cache = {}
	if M.is_readable(path, read_cache) then
		return path
	end
	local v_path = filter_path(path, cwd, read_cache)
	if v_path and M.is_readable(v_path, read_cache) then
		return v_path
	else
		return nil
	end
end

return M
