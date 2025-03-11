local M = {}
local util = require("oz.util")

local data_dir = vim.fn.stdpath("data")
local uv = vim.loop

-- remove json
function M.remove_oz_json(name)
	local path = data_dir .. "/oz/" .. name .. ".json"
	if vim.fn.filereadable(path) == 1 then
		os.remove(path)
		util.Notify("oz: cache remove: " .. name)
	end
end

-- ensure file exists
local function file_exists(filepath)
	local stat = uv.fs_stat(filepath)
	return stat and stat.type == "file"
end

-- ensure dir exists
local function ensure_dir(filepath)
	local dir = filepath:match("(.+)/[^/]+$")
	if dir then
		local cmd = { "mkdir", "-p", dir }
        util.ShellCmd(cmd, nil, function ()
            error("oz: something went wrong while creating dir.")
        end)
	end
end

-- set data
function M.set_data(key, value, json_name)
	-- Ensure parent directory exists.
	local json_file = data_dir .. "/oz/" .. json_name .. ".json"
	ensure_dir(json_file)

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
				else
                    util.Notify("Failed to decode JSON from " .. json_file, "warn")
				end
			end
		else
			util.Notify("Failed to open file " .. json_file, "error")
		end
	end

	-- Update the data with the provided key and value.
	data[key] = value

	-- Encode table back to JSON.
	local new_content = vim.fn.json_encode(data)

	-- Write back the content to file.
	local f = io.open(json_file, "w")
	if f then
		f:write(new_content)
		f:close()
	else
        util.Notify("oz: Error occurred while writing data to " .. json_name, "error")
	end
end

function M.get_data(key, json_name)
    json_name = data_dir .. "/oz/" .. json_name .. ".json"

    if not file_exists(json_name) then
        util.Notify("oz: File does not exist: " .. json_name, "warn")
        return nil
    end

    local file = io.open(json_name, "r")
    if not file then
        util.Notify("oz: Failed to open file: " .. json_name, "error")
        return nil
    end

    local content = file:read("*a")
    file:close()

    if not content or content == "" then
        util.Notify("oz: File is empty: " .. json_name, "warn")
        return nil
    end

    local ok, data = pcall(vim.fn.json_decode, content)
    if not ok then
        util.Notify("oz: Failed to decode JSON from " .. json_name, "error")
        return nil
    end

    return data[key]
end

-- set project cmd
function M.setprojectCMD(project_path, file, ft, cmd)
	local key = [[{project_path}${ft}]]
	key = key:gsub("{project_path}", project_path):gsub("{ft}", ft)

	-- if more than one file name in cmd
	local filenames = {} -- we can use file name in future
	for filename in cmd:gmatch("[%w%-%_%.]+%.[%w]+") do
		table.insert(filenames, filename)
	end
	if #filenames == 1 then
		if cmd:find(file) then
			cmd = cmd:gsub(file, "{filename}")
		end
	end

	M.set_data(key, cmd, "data")
end

-- get project cmd
function M.getprojectCMD(project_path, file, ft)
	local key = [[{project_path}${ft}]]
	key = key:gsub("{project_path}", project_path):gsub("{ft}", ft)

	local out = M.get_data(key, "data")
	if out and out:find("{filename}") then
		out = out:gsub("{filename}", file)
	end
	return out
end

-- set ft cmd
function M.setftCMD(file, ft, cmd)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end
	if cmd:find(file) then
		cmd = cmd:gsub(file, "{filename}")
	end

	M.set_data(ft, cmd, "ft")
end

-- get ft cmd
function M.getftCMD(file, ft)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end

	local output = M.get_data(ft, "ft")

	if output and output:find("{filename}") then
		output = output:gsub("{filename}", file)
	end
	return output
end

return M
