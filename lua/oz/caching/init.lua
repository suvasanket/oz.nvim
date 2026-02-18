local M = {}
local util = require("oz.util")

local data_dir = vim.fn.stdpath("data")
local uv = vim.loop

--- Remove a JSON cache file.
--- @param name string The name of the cache.
function M.remove_oz_json(name)
	local path = data_dir .. "/oz/" .. name .. ".json"
	if vim.fn.filereadable(path) == 1 then
		os.remove(path)
        util.Notify("[cache]Cache removed: " .. name, "info", "oz_doctor")
	end
end

--- Internal helper: Check if a file exists.
--- @param filepath string
--- @return boolean
local function file_exists(filepath)
	local stat = uv.fs_stat(filepath)
	return stat ~= nil and stat.type == "file"
end

--- Internal helper: Write content to a file, creating directories if needed.
--- @param full_path string
--- @param content string
local function write_to_file(full_path, content)
	local dir_path = full_path:match("^(.*/)")

	local function create_dir(path)
		local cmd = "mkdir -p " .. path
		if vim.fn.has("win32") == 1 then
			cmd = "mkdir " .. path .. "^& exit"
		end
		vim.fn.system(cmd)
	end

	if dir_path and dir_path ~= "" then
		create_dir(dir_path)
	end

	local file = io.open(full_path, "w")
	if file then
		file:write(content)
		file:close()
	else
        util.Notify("[cache] Failed to open file.", "error", "oz_doctor")
	end
end

--- Set a value in a JSON cache.
--- @param key string The key to set.
--- @param value any The value to set (nil/empty string to remove).
--- @param json_name string The name of the cache file.
function M.set_data(key, value, json_name)
	local json_file = data_dir .. "/oz/" .. json_name .. ".json"

	if value == "" then
		value = nil
	end

	local data = {}
	if file_exists(json_file) then
		local f = io.open(json_file, "r")
		if f then
			local content = f:read("*a")
			f:close()
			if content and #content > 0 then
				local ok, decoded = pcall(vim.fn.json_decode, content)
				if ok and type(decoded) == "table" then
					data = decoded
				end
			end
		end
	end

	data[key] = value
	local new_content = vim.fn.json_encode(data)
	write_to_file(json_file, new_content)
end

--- Get a value from a JSON cache.
--- @param key string The key to retrieve.
--- @param json_name string The name of the cache file.
--- @return any|nil The cached value.
function M.get_data(key, json_name)
	local full_path = data_dir .. "/oz/" .. json_name .. ".json"

	if not file_exists(full_path) then
		return nil
	end

	local file = io.open(full_path, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()

	if not content or content == "" then
		return nil
	end

	local ok, data = pcall(vim.fn.json_decode, content)
	if not ok or type(data) ~= "table" then
		return nil
	end

	return data[key]
end

return M
