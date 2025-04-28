local M = {}

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

function M.run_command(cmd, cwd)
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
			-- Filter out empty lines often added by jobstart/shell
			for _, line in ipairs(data) do
				table.insert(stdout_lines, line)
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				table.insert(stderr_lines, line)
			end
		end,
		on_exit = function(_, code)
			exit_code = code
		end,
	})

	if not job_id or job_id <= 0 then
		return false, cmd
	end

	local result = vim.fn.jobwait({ job_id }, -1)
	local final_code = (result and result[1] == -1) and exit_code or (result and result[1]) or -1

	if final_code == 0 then
		return true, trim_empty_strings(stdout_lines)
	else
		return false, trim_empty_strings(stderr_lines)
	end
end

function M.shellout_str(str, cwd)
	local ok, output = M.run_command(str, cwd)
	if ok then
		local final_out = #output == 1 and output[1] or table.concat(output, "\n")
		return final_out
	else
		return ""
	end
end

function M.shellout_tbl(str, cwd)
	local ok, output = M.run_command(str, cwd)
	if ok then
		return output
	else
		return {}
	end
end

return M
