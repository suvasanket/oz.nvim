local M = {}
local util = require("oz.util")
local cache = require("oz.caching")

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

	cache.set_data(key, cmd, "data")
end

local function getprojectCMD(project_path, file, ft)
	local key = [[{project_path}${ft}]]
	key = key:gsub("{project_path}", project_path):gsub("{ft}", ft)

	local out = cache.get_data(key, "data")
	if out and out:find("{filename}") then
		out = out:gsub("{filename}", file)
	end
	return out
end

local function setftCMD(file, ft, cmd)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end
	if cmd:find(file) then
		cmd = cmd:gsub(file, "{filename}")
	end

	cache.set_data(ft, cmd, "ft")
end

local function getftCMD(file, ft)
	if file:match("%.") then
		file = vim.fn.fnamemodify(file, ":r")
	end

	local output = cache.get_data(ft, "ft")

	if output and output:find("{filename}") then
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
function M.predict_compiler(current_file, ft)
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
function M.cmd_func(type, func)
	local current_file = vim.fn.expand("%")
	local ft = vim.bo.filetype
	local shebang = M.detect_shebang()
	local project_path = util.GetProjectRoot() -- may return nil
	-- p: 1
	if not shebang then
		-- p: 2 , 3
		local cmd
		if project_path then
			cmd = getprojectCMD(project_path, current_file, ft) or getftCMD(current_file, ft)
		else
			cmd = getftCMD(current_file, ft)
		end
		if not cmd then
			-- p: 4
			cmd = M.predict_compiler(current_file, ft)
		end
		local input = util.inactive_input(":" .. type .. " ", cmd, "shellcmd")

		if input and input ~= "" then
			-- custom function, used for AKTUAL execution
			if func then
				func(input, cmd)
			else
				vim.cmd(type .. " " .. input)
			end

			-- check if its a valid cmd or not
			-- if vim.fn.executable(input:match("^%s*@?([%w/%.-]+)")) == 1 then
			if cmd ~= input and project_path then
				setprojectCMD(project_path, current_file, ft, input)
			end
			if input:find(current_file) then
				if project_path then
					setprojectCMD(project_path, current_file, ft, input)
				else
					setftCMD(current_file, ft, input)
				end
			end
			-- end
		elseif input == "" then
			util.Notify("Term requires at least one command to start.", "warn", "oz_term")
		end
	else
		vim.api.nvim_feedkeys(":" .. type .. " " .. shebang .. " " .. current_file, "n", false)
	end
end

return M
