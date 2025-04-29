local M = {}
local util = require("oz.util")

local data_dir = vim.fn.stdpath("data")
local uv = vim.loop

-- remove json
function M.remove_oz_json(name)
	local path = data_dir .. "/oz/" .. name .. ".json"
	if vim.fn.filereadable(path) == 1 then
		os.remove(path)
		util.Notify("[cache]Cache removed: " .. name, "info", "oz_doctor")
	end
end

-- ensure file exists
local function file_exists(filepath)
	local stat = uv.fs_stat(filepath)
	return stat and stat.type == "file"
end

-- write to the file
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

	-- Write the content to the file
	local file = io.open(full_path, "w")
	if file then
		file:write(content)
		file:close()
	else
		util.Notify("[cache] Failed to open file.", "error", "oz_doctor")
	end
end

-- set data
function M.set_data(key, value, json_name)
	-- Ensure parent directory exists.
	local json_file = data_dir .. "/oz/" .. json_name .. ".json"

	-- delete empty value
	if value == "" then
		value = nil
	end

	-- Read the JSON file (if exists) or start with an empty table.
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

	-- Update the data with the provided key and value.
	data[key] = value

	-- Encode table back to JSON.
	local new_content = vim.fn.json_encode(data)

	-- Write back the content to file.
	write_to_file(json_file, new_content)
end

function M.get_data(key, json_name)
	json_name = data_dir .. "/oz/" .. json_name .. ".json"

	if not file_exists(json_name) then
		return nil
	end

	local file = io.open(json_name, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()

	if not content or content == "" then
		return nil
	end

	local ok, data = pcall(vim.fn.json_decode, content)
	if not ok then
		return nil
	end

	return data[key]
end

return M
