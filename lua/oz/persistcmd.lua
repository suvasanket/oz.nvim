local M = {}
local util = require("oz.util")

local data_dir = vim.fn.stdpath("data")
local data_json = data_dir .. "/oz/data.json"
local ft_json = data_dir .. "/oz/ft.json"
local termbang_json = data_dir .. "/oz/termbang.json"
local oil_json = data_dir .. "/oz/oilcmd.json"

-- generate the command to get from json file
local function gen_setcmd(key, value, json_path)
	local data_writecmd = [[
    mkdir -p "{data_dir}" && [ -f "{json_path}" ] || echo '{}' > "{json_path}" && jq '. + {"{key}": "{value}"}' "{json_path}" > oz_temp.json && mv oz_temp.json "{json_path}"
    ]]
	data_writecmd = data_writecmd
		:gsub("{json_path}", json_path)
		:gsub("{data_dir}", data_dir .. "/oz")
		:gsub("{key}", key)
		:gsub("{value}", value)
	return data_writecmd
end

-- generate the command to set data to json file
local function gen_getcmd(key, json_path)
	local data_readcmd = [[
    jq -r '."{key}"'  "{json_path}"
    ]]
	return data_readcmd:gsub("{key}", key):gsub("{json_path}", json_path)
end

-- remove oz_temp.json if error
local function remove_tempjson()
	util.ShellCmd('[ -f "oz_temp.json" ] && rm oz_temp.json', function()
		print("oz(error): temp files removed")
	end, nil)
end

-- set file cmd
function M.setpersistCMD(project_path, file, ft, cmd)
	local key = [[{project_path}${ft}]]
	key = key:gsub("{project_path}", project_path):gsub("{ft}", ft)
	if cmd:find(file) then
		cmd = cmd:gsub(file, "{filename}")
	end

	util.ShellCmd(gen_setcmd(key, cmd, data_json), nil, function()
		util.Notify("error occured saving command", "error", "Error")
		remove_tempjson()
	end)
end

-- get file cmd
function M.getpersistCMD(project_path, file, ft)
	local key = [[{project_path}${ft}]]
	key = key:gsub("{project_path}", project_path):gsub("{ft}", ft)

	local out = util.ShellOutput(gen_getcmd(key:gsub("/", "\\/"), data_json))
	if out and out ~= "null" then
		if out:find("{filename}") then
			out = out:gsub("{filename}", file)
		end
		return out
	else
		return nil
	end
end

-- set ft cmd
function M.setftCMD(file, ft, cmd)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end
	if cmd:find(file) then
		cmd = cmd:gsub(file, "{filename}")
	end

	util.ShellCmd({ "sh", "-c", gen_setcmd(ft, cmd, ft_json) }, nil, function()
		util.Notify("error occured saving ft command", "error", "Error")
		remove_tempjson()
	end)
end

-- get ft cmd
function M.getftCMD(file, ft)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end

	local output = util.ShellOutput(gen_getcmd(ft, ft_json))

	if output and output ~= "null" then
		if output:find("{filename}") then
			output = output:gsub("{filename}", file)
		end
		return output
	else
		return nil
	end
end

-- set Term! cmd
function M.setTermBcmd(current_file, cmd)
	util.ShellCmd({ "sh", "-c", gen_setcmd(current_file, cmd, termbang_json) }, nil, function()
		util.Notify("error occured saving Term! command", "error", "Error")
		remove_tempjson()
	end)
end

-- get Term! cmd
function M.getTermBcmd(current_file)
	local output = util.ShellOutput(gen_getcmd(current_file, termbang_json))

	if output and output ~= "null" then
		return output
	else
		return nil
	end
end

-- set oil cmd
function M.setoilcmd(cwd, cmd)
	cmd = cmd:gsub('"', '\\"')

	util.ShellCmd({ "sh", "-c", gen_setcmd(cwd, cmd, oil_json) }, nil, function()
		util.Notify("error occured saving oil command", "error", "Error")
		remove_tempjson()
	end)
end

-- get oil cmd
function M.getoilcmd(cwd)
	local output = util.ShellOutput(gen_getcmd(cwd:gsub("/", "\\/"), oil_json))

	if output and output ~= "null" then
		return output
	else
		return nil
	end
end

return M
