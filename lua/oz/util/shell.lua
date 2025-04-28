local M = {}

function M.run_command(cmd_table, cwd)
	local stdout_lines = {}
	local stderr_lines = {}
	local exit_code = -1
	if not cwd then
		cwd = vim.fn.getcwd()
	end

	local job_id = vim.fn.jobstart(cmd_table, {
		cwd = cwd,
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			-- Filter out empty lines often added by jobstart/shell
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(stdout_lines, line)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(stderr_lines, line)
				end
			end
		end,
		on_exit = function(_, code)
			exit_code = code
		end,
	})

	if not job_id or job_id <= 0 then
		return false, "Failed to start job for command: " .. table.concat(cmd_table, " ")
	end

	-- Wait indefinitely for the job to complete
	local result = vim.fn.jobwait({ job_id }, -1)
	-- Use the exit_code captured by the on_exit callback
	local final_code = (result and result[1] == -1) and exit_code or (result and result[1]) or -1

	if final_code == 0 then
		return true, table.concat(stdout_lines, "\n")
	else
		local err_msg = "Command failed with code " .. final_code .. ": " .. table.concat(cmd_table, " ")
		if #stderr_lines > 0 then
			err_msg = err_msg .. "\nStderr:\n" .. table.concat(stderr_lines, "\n")
		end
		return false, err_msg
	end
end

return M
