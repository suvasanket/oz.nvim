local M = {}

local util = require("oz.util")

local function parse_search_cmd(cmd)
	local tokens = {}
	for token in cmd:gmatch("%S+") do
		table.insert(tokens, token)
	end

	local result = {
		exe = tokens[1] or "",
		flags = {},
		pattern = "",
		target = nil,
	}

	local non_flag_tokens = {}

	for i = 2, #tokens do
		local token = tokens[i]
		if token:sub(1, 1) == "-" then
			table.insert(result.flags, token)
		else
			table.insert(non_flag_tokens, token)
		end
	end

	if #non_flag_tokens >= 1 then
		local pat = non_flag_tokens[1]
		pat = pat:gsub("^[\"']", ""):gsub("[\"']$", "")
		result.pattern = pat
	end

	if #non_flag_tokens >= 2 then
		result.target = non_flag_tokens[2]
	end

	return result
end

-- check if cmd is grep or not
function M.cmd_contains_grep(cmd)
	local grep_commands = { "rg", "grep" }

	for _, grep_cmd in ipairs(grep_commands) do
		local pattern = string.format("%%f[%%w]%s%%f[%%W]", grep_cmd)
		if cmd:match(pattern) then
			return true
		end
	end
	return false
end

-- grep -> qf
function M.grep_to_qf(cmd, dir)
	local parsed = parse_search_cmd(cmd)
	local flags = parsed.flags
	local exe = parsed.exe
	local target = dir or parsed.target or "."

	local rg_flags = { "--vimgrep", "--color=never" }
	local grep_flags = { "-nrH", "--color=never" }

	if exe == "rg" then
		M.async_grep(exe, parsed.pattern, target, {
			flags = vim.tbl_deep_extend("keep", rg_flags, flags),
			formatter = "%f:%l:%c:%*\\t%m",
		})
	elseif exe == "grep" then
		M.async_grep(exe, parsed.pattern, target, {
			flags = vim.tbl_deep_extend("keep", grep_flags, flags),
			formatter = "%f:%l:%m",
		})
	end
end

-- async grep
function M.async_grep(cmd, pattern, dir, opts)
	opts = opts or {}
	local formatter = opts.formatter
	local args = {}

	if opts.flags then
		for _, a in ipairs(opts.flags) do
			table.insert(args, a)
		end
	end

	table.insert(args, pattern)
	if dir then
		table.insert(args, dir)
	end

	local output_lines = {}

	---@diagnostic disable-next-line: deprecated
	vim.fn.jobstart({ cmd, unpack(args) }, {
		stdout_buffered = true,
		on_stdout = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(output_lines, line)
					end
				end
			end
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						vim.notify(cmd .. " error: " .. line, vim.log.levels.ERROR)
					end
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			if exit_code == 0 or exit_code == 1 then
				vim.fn.setqflist({}, " ", {
					lines = output_lines,
					efm = formatter,
				})
				if #vim.fn.getqflist() > 0 then
					vim.cmd("copen")
				else
					vim.notify("No matches found", vim.log.levels.INFO)
				end
			else
				vim.notify(cmd .. " exited with code: " .. exit_code, vim.log.levels.ERROR)
			end
		end,
	})
end

return M
