local M = {}
local util = require("oz.util")

local data_dir = vim.fn.stdpath("data")

-- generate the command to get from json file
local function gen_setcmd(key, value, json)
	if not key or not value then
		return
	end
	json = data_dir .. "/oz/" .. json .. ".json"

	local jq_cmd = [[jq '. + {"{key}": "{value}"}' "{json_path}"]]
	local data_writecmd = [[
    mkdir -p "{data_dir}" && [ -f "{json_path}" ] || echo '{}' > "{json_path}" && {jq_cmd} > oz_temp.json && mv oz_temp.json "{json_path}"
    ]]
	-- modify for set
	value = value:gsub('"', '\\"')
	data_writecmd = data_writecmd
		:gsub("{jq_cmd}", jq_cmd)
		:gsub("{json_path}", json)
		:gsub("{data_dir}", data_dir .. "/oz")
		:gsub("{key}", key)
		:gsub("{value}", value)
	return data_writecmd
end

-- generate the command to set data to json file
local function gen_getcmd(key, json)
	if not key then
		return
	end
	json = data_dir .. "/oz/" .. json .. ".json"

	local data_readcmd = [[
    jq -r '."{key}"'  "{json_path}"
    ]]
	return data_readcmd:gsub("{key}", key):gsub("{json_path}", json)
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
		util.Notify("Error: temp files removed.", "error", "Oz")
	end, nil)
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

	util.ShellCmd(gen_setcmd(key, cmd, "data"), nil, function()
		util.Notify("error occured saving command.", "error", "Error")
		remove_tempjson()
	end)
end

-- get project cmd
function M.getprojectCMD(project_path, file, ft)
	local key = [[{project_path}${ft}]]
	key = key:gsub("{project_path}", project_path):gsub("{ft}", ft)

	local out = util.ShellOutput(gen_getcmd(key:gsub("/", "\\/"), "data"))
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

	util.ShellCmd({ "sh", "-c", gen_setcmd(ft, cmd, "ft") }, nil, function()
		util.Notify("error occured saving ft command.", "error", "Error")
		remove_tempjson()
	end)
end

-- get ft cmd
function M.getftCMD(file, ft)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end

	local output = util.ShellOutput(gen_getcmd(ft, "ft"))

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
	util.ShellCmd({ "sh", "-c", gen_setcmd(current_file, cmd, "termbang") }, nil, function()
		util.Notify("error occured saving Term! command.", "error", "Error")
		remove_tempjson()
	end)
end

-- get Term! cmd
function M.getTermBcmd(current_file)
	local output = util.ShellOutput(gen_getcmd(current_file, "termbang"))

	if output and output ~= "null" then
		return output
	else
		return nil
	end
end

-- set oil cmd
function M.setoilcmd(cwd, cmd)
	util.ShellCmd({ "sh", "-c", gen_setcmd(cwd, cmd, "oilcmd") }, nil, function()
		util.Notify("error occured saving oil command.", "error", "Error")
		remove_tempjson()
	end)
end

-- get oil cmd
function M.getoilcmd(cwd)
	local output = util.ShellOutput(gen_getcmd(cwd:gsub("/", "\\/"), "oilcmd"))

	if output and output ~= "null" then
		return output
	else
		return nil
	end
end

-- set makeprg
function M.set_makeprg(path, makeprg)
	util.ShellCmd({ "sh", "-c", gen_setcmd(path, makeprg, "makeprg") }, nil, function()
		util.Notify("error occured, saving makeprg.", "error", "Error")
		remove_tempjson()
	end)
end

-- get makeprg
function M.get_makeprg(path)
	local output = util.ShellOutput(gen_getcmd(path:gsub("/", "\\/"), "makeprg"))

	if output and output ~= "null" then
		return output
	else
		return nil
	end
end

return M
