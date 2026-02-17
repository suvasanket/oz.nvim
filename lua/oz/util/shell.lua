--- @class oz.util.shell
local M = {}

--- Trim empty strings from the beginning and end of a table.
--- @param tbl string[] The table of strings.
--- @return string[] The trimmed table.
local function trim_empty_strings(tbl)
	local start = 1
	while start <= #tbl and tbl[start] == "" do
		start = start + 1
	end

	local finish = #tbl
	while finish >= 1 and tbl[finish] == "" do
		finish = finish - 1
	end

	local result = {}
	for i = start, finish do
		table.insert(result, tbl[i])
	end

	return result
end

--- Run a shell command and return the result.
--- @param cmd string|string[] The command to execute.
--- @param cwd? string Optional working directory.
--- @param opts? {trim_off: boolean} Optional options.
--- @return boolean success True if the command exited with code 0.
--- @return string[] output The command output (stdout or stderr).
function M.run_command(cmd, cwd, opts)
	local stdout_lines = {}
	local stderr_lines = {}
	local exit_code = -1
	if not cwd then
		cwd = vim.fn.getcwd()
	end

	cmd = type(cmd) == "string" and require("oz.util.parse_args").parse_args(cmd) or cmd

	local job_id = vim.fn.jobstart(cmd, {
		cwd = cwd,
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					table.insert(stdout_lines, line)
				end
			end
		end,
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					table.insert(stderr_lines, line)
				end
			end
		end,
		on_exit = function(_, code)
			exit_code = code
		end,
	})

	if not job_id or job_id <= 0 then
		return false, {}
	end

	local result = vim.fn.jobwait({ job_id }, -1)
	local final_code = (result and result[1] == -1) and exit_code or (result and result[1]) or -1

	if final_code == 0 then
		if opts and opts.trim_off then
			return true, stdout_lines
		else
			return true, trim_empty_strings(stdout_lines)
		end
	else
		return false, trim_empty_strings(stderr_lines)
	end
end

--- Run a shell command and return the output as a trimmed string.
--- @param str string|string[] The command string.
--- @param cwd? string Optional working directory.
--- @return string output The command output.
function M.shellout_str(str, cwd)
	local ok, output = M.run_command(str, cwd)
	if ok then
		local final_out = #output == 1 and output[1] or table.concat(output, "\n")
		return vim.trim(final_out)
	else
		return ""
	end
end

--- Run a shell command and return the output as a table of lines.
--- @param str string|string[] The command string.
--- @param cwd? string Optional working directory.
--- @return string[] output The command output as lines.
function M.shellout_tbl(str, cwd)
	local ok, output = M.run_command(str, cwd)
	if ok then
		return output
	else
		return {}
	end
end

return M
