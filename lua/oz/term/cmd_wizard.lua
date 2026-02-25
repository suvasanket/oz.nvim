local M = {}
local util = require("oz.util")

function M.detect_compiler(ft)
	-- Try common suffix variations dynamically
	local candidates = { ft .. "c", ft }
	for _, candidate in ipairs(candidates) do
		if vim.fn.executable(candidate) == 1 then
			return candidate
		end
	end

	-- Check if there's a compiler script in runtimepath
	local runtime_compiler = vim.fn.globpath(vim.o.runtimepath, "compiler/" .. ft .. ".vim")
	if runtime_compiler ~= "" then
		return ft
	end

	return nil
end

local function setprojectCMD(project_path, file, ft, cmd)
	local key = string.format("%s$%s", project_path, ft)

	-- if more than one file name in cmd
	local filenames = {} -- we can use file name in future
	for filename in cmd:gmatch("[%w%-%_%.]+%.[%w]+") do
		table.insert(filenames, filename)
	end
	if #filenames == 1 then
		if cmd:find(file, 1, true) then
			cmd = cmd:gsub(vim.pesc(file), "{filename}")
		end
	end

	require("oz.caching").set_data(key, cmd, "data")
end

local function getprojectCMD(project_path, file, ft)
	local key = string.format("%s$%s", project_path, ft)

	local out = require("oz.caching").get_data(key, "data")
	if out and out:find("{filename}", 1, true) then
		out = out:gsub("{filename}", file)
	end
	return out
end

local function setftCMD(file, ft, cmd)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end
	if cmd:find(file, 1, true) then
		cmd = cmd:gsub(vim.pesc(file), "{filename}")
	end

	require("oz.caching").set_data(ft, cmd, "ft")
end

local function getftCMD(file, ft)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end

	local output = require("oz.caching").get_data(ft, "ft")

	if output and output:find("{filename}", 1, true) then
		output = output:gsub("{filename}", file)
	end
	return output
end

-- detect any shebang in the file
function M.detect_shebang()
	local first_line = vim.fn.getline(1)
	local shebang_match = first_line:match("^#!%s*(%S+)")
	if shebang_match and vim.fn.executable(shebang_match) == 1 then
		return shebang_match
	end
	return nil
end

-- detect makeprg exist for current ft or not
function M.detect_makeprg(filename)
	local makeprg = vim.fn.getbufvar("%", "&makeprg")

	if makeprg and makeprg ~= "" then
		local file_no_ext = vim.fn.fnamemodify(filename, ":r")
		local file_basename = vim.fn.fnamemodify(filename, ":t")
		local file_dir = vim.fn.fnamemodify(filename, ":h")

		makeprg = makeprg
			:gsub("%%:t:r", file_no_ext)
			:gsub("%%:t", file_basename)
			:gsub("%%:r", file_no_ext)
			:gsub("%%:p:h", file_dir)
			:gsub("%%", filename)

		return makeprg
	end
	return nil
end

-- predict the compiler then concat with the current file
---@param current_file string
---@param ft string
---@return string
function M.predict_compiler(current_file, ft)
	local shebang = M.detect_shebang()
	if shebang then
		return string.format("%s %s", shebang, current_file)
	end
	local makeprg = M.detect_makeprg(current_file)
	if makeprg == "make" or not makeprg then
		local compiler = M.detect_compiler(ft)
		if compiler then
			return compiler .. " " .. current_file
		else
			return ""
		end
	else
		return makeprg
	end
end

-- run command for both Compile-Term
---@param prefix string
---@param func function<string>
function M.cmd_func(prefix, func)
	local current_file = vim.fn.expand("%")
	local ft = vim.bo.filetype
	local project_path = util.GetProjectRoot()
	local cmd = nil

	if project_path then
		cmd = getprojectCMD(project_path, current_file, ft) or getftCMD(current_file, ft)
	else
		cmd = getftCMD(current_file, ft)
	end
	-- no cached data --
	if not cmd then
		cmd = M.predict_compiler(current_file, ft)
	end
	-- take userinput --
	local input = util.inactive_input(":" .. prefix .. " ", cmd, "shellcmd")

	if input and input ~= "" then
		-- custom function, used for AKTUAL execution
		if func then
			func(input, cmd)
		else
			vim.cmd(prefix .. " " .. input)
		end

		-- caching --
		if cmd ~= input and project_path then -- if cmd is different and in project then cache it.
			setprojectCMD(project_path, current_file, ft, input)
		end
		if input:find(current_file, 1, true) then -- if cmd contains current file
			if project_path then
				setprojectCMD(project_path, current_file, ft, input)
			else
				setftCMD(current_file, ft, input)
			end
		end
	elseif input == "" then
		util.Notify("Provide a cmd!", "warn", "oz_term")
	end
end

return M
