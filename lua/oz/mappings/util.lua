local M = {}
local util = require("oz.util")
local p = require("oz.caching")

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
			cmd = p.getprojectCMD(project_path, current_file, ft) or p.getftCMD(current_file, ft)
		else
			cmd = p.getftCMD(current_file, ft)
		end
		if not cmd then
			-- p: 4
			cmd = M.predict_compiler(current_file, ft)
		end
		local input = util.UserInput(":" .. type .. " ", cmd)
		if input and input ~= "" then
			-- custom function, used for AKTUAL execution
			if func then
				func(input, cmd)
			else
				vim.cmd(type .. " " .. input)
			end

			-- check if its a valid cmd or not
            if vim.fn.executable(input:match("^%s*@?([%w/%.-]+)")) == 1 then
				if cmd ~= input and project_path then
					p.setprojectCMD(project_path, current_file, ft, input)
				end
				if input:find(current_file) then
					if project_path then
						p.setprojectCMD(project_path, current_file, ft, input)
					else
						p.setftCMD(current_file, ft, input)
					end
				end
			end
		elseif input == "" then
			util.Notify("oz: oz_term requires at least one command to start.", "warn", "oz")
		end
	else
		vim.api.nvim_feedkeys(":" .. type .. " " .. shebang .. " " .. current_file, "n", false)
	end
end

return M
