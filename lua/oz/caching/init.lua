local M = {}
local util = require("oz.util")

local data_dir = vim.fn.stdpath("data")

-- encode json
local function encode_json(str)
	local json_encoded = vim.fn.json_encode(str)
	return json_encoded:sub(2, -2)
end

-- decode json
local function decode_json(escaped_string)
	local json_string = '"' .. escaped_string .. '"'
	return vim.fn.json_decode(json_string)
end

function M.remove_oz_json(name)
	local path = data_dir .. "/oz/" .. name .. ".json"
	if vim.fn.filereadable(path) == 1 then
		os.remove(path)
		util.Notify("oz: cache remove: " .. name)
	end
end

-- remove oz_temp.json if error
local function remove_tempjson()
	util.ShellCmd('[ -f "oz_temp.json" ] && rm oz_temp.json', function()
		util.Notify("Error: temp files removed.", "error", "oz")
	end, nil)
end

local function set_data(key, value, json)
	if not key or not value then
		return
	end
	json = data_dir .. "/oz/" .. json .. ".json"
	key = encode_json(key)
	value = encode_json(value)

	local jq_cmd = string.format([[jq '. + {"%s": "%s"}' "%s"]], key, value, json)
	local write_cmd = string.format(
		[[mkdir -p "%s" && [ -f "%s" ] || echo '{}' > "%s" && %s > oz_temp.json && mv oz_temp.json "%s"]],
		data_dir .. "/oz",
		json,
		json,
		jq_cmd,
		json
	)

	-- shell
	util.ShellCmd(write_cmd, function()
		return true
	end, function()
		util.Notify("error occured caching command.", "error", "Error")
		remove_tempjson()
		return false
	end)
end

local function get_data(key, json)
	if not key then
		return
	end
	json = data_dir .. "/oz/" .. json .. ".json"
	key = encode_json(key)
	local read_cmd = string.format([[jq -r '."%s"'  "%s"]], key, json)
	local som = util.ShellOutput(read_cmd)
	if som and som ~= "null" then
		return som
	else
		return nil
	end
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

	set_data(key, cmd, "data")
end

-- get project cmd
function M.getprojectCMD(project_path, file, ft)
	local key = [[{project_path}${ft}]]
	key = key:gsub("{project_path}", project_path):gsub("{ft}", ft)

	local out = get_data(key, "data")
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

	set_data(ft, cmd, "ft")
end

-- get ft cmd
function M.getftCMD(file, ft)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end

	local output = get_data(ft, "ft")

	if output and output:find("{filename}") then
		output = output:gsub("{filename}", file)
	end
	return output
end

-- set Term! cmd
function M.setTermBcmd(current_file, cmd)
	set_data(current_file, cmd, "termbang")
end

-- get Term! cmd
function M.getTermBcmd(current_file)
	local output = get_data(current_file, "termbang")

	return output
end

-- set oil cmd
function M.setoilcmd(cwd, cmd)
	set_data(cwd, cmd, "oilcmd")
end

-- get oil cmd
function M.getoilcmd(cwd)
	local output = get_data(cwd, "oilcmd")

	return output
end

-- set makeprg
function M.set_makeprg(path, makeprg)
	set_data(path, makeprg, "makeprg")
end

-- get makeprg
function M.get_makeprg(path)
	local output = get_data(path, "makeprg")

	return output
end

-- set ft efm
function M.set_ft_efm(ft, fmt)
	set_data(ft, fmt, "ft_efm")
end

-- get ft efm
function M.get_ft_efm(ft)
	local output = get_data(ft, "ft_efm")

	return output
end

return M
