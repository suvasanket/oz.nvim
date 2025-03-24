local M = {}
-- local util = require("oz.util")

function M.expand_expressions(str)
	local pattern = "%%[:%w]*"

	local expanded_str = string.gsub(str, pattern, function(exp)
		return vim.fn.expand(exp)
	end)

	return expanded_str
end

function M.parse_args(argstring)
	local args = {}
	local i = 1
	local len = #argstring

	while i <= len do
		while i <= len and argstring:sub(i, i):match("%s") do
			i = i + 1
		end
		if i > len then
			break
		end
		if argstring:sub(i, i) == '"' or argstring:sub(i, i) == "'" then
			local quote = argstring:sub(i, i)
			local start = i + 1
			i = i + 1
			while i <= len and argstring:sub(i, i) ~= quote do
				i = i + 1
			end

			if i <= len then
				table.insert(args, argstring:sub(start, i - 1))
				i = i + 1
			else
				table.insert(args, argstring:sub(start))
			end
		else
			local start = i
			while i <= len and not argstring:sub(i, i):match("%s") do
				i = i + 1
			end

			table.insert(args, argstring:sub(start, i - 1))
		end
	end

	return args
end

function M.check_flags(tbl, flag)
	for _, str in pairs(tbl) do
		if str:find(flag) then
			return true
		end
	end
	return false
end

function M.save_lines_to_commitfile(lines)
	local git_dir_command = "git rev-parse --git-dir 2>/dev/null"
	local git_dir = vim.fn.system(git_dir_command):gsub("%s+$", "")

	if vim.v.shell_error ~= 0 then
		return
	end

	local commit_msg_file = git_dir .. "/COMMIT_EDITMSG"

	local file = io.open(commit_msg_file, "w")
	if file then
		-- Write all lines to the file
		for _, line in ipairs(lines) do
			file:write(line .. "\n")
		end
		file:close()
	end
end

function M.set_cmdline(str)
	local cmdline = str:gsub("%|", "")
	vim.api.nvim_feedkeys(":" .. cmdline, "n", false)
	local cursor_pos = str:find("%|")
	if cursor_pos then
		vim.api.nvim_input(string.rep("<Left>", #str - cursor_pos))
	end
end

return M
