local M = {}
local util = require("oz.util")

-- Clean ANSI codes and carriage returns from lines
local function clean_line(line)
	return line and line:gsub("\r", ""):gsub("\27%[%d+[mK]", "") or ""
end

-- open output for specific cmds
local function cmd_output(cmd, output)
	local cmds = { "request-pull", "ls-remote" }
	if util.str_in_tbl(cmd, cmds) then
		require("oz.git.oz_git_win").open_oz_git_win(output, cmd)
	end
end

-- Main git async function
function M.run_git_with_progress(command, args, output_callback)
	local cmd = table.concat({ "git", command, unpack(args or {}) }, " ")
	local title = "git " .. command:sub(1, 1) .. command:sub(2)

	local all_output = {}
	local stdout_lines = { "" }
	local stderr_lines = { "" }

	local u_id = util.generate_unique_id()
	util.start_progress(u_id, { title = title, fidget_lsp = "oz_git", manual = true })

	local function handle_data(lines_table, data)
		if not data then
			return
		end

		-- Append to lines buffer (handling stream chunks)
		lines_table[#lines_table] = lines_table[#lines_table] .. data[1]
		for i = 2, #data do
			lines_table[#lines_table + 1] = data[i]
		end

		-- Check for progress in the raw data chunks
		for _, str in ipairs(data) do
			local last_p = nil
			-- Find the last percentage in the chunk (handling multiple updates like "10% \r 20%")
			for p in str:gmatch("(%d+)%%") do
				last_p = p
			end

			if last_p then
				local msg = clean_line(str)
				-- Optional: Truncate message if too long or noisy?
				-- Git progress often includes counts (123/456), which is useful.
				util.update_progress(u_id, tonumber(last_p), msg)
			end
		end
	end

	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data)
			handle_data(stdout_lines, data)
		end,
		on_stderr = function(_, data)
			handle_data(stderr_lines, data)
		end,
		on_exit = function(_, exit_code)
			util.stop_progress(u_id, { exit_code = exit_code, title = title })

			-- Consolidate output for callback/display
			-- Filter out pure progress lines if desired, or just show all cleaned lines.
			-- Usually we want to see the errors or diffs.
			local function collect_lines(lines)
				for _, line in ipairs(lines) do
					if line ~= "" then
						-- Heuristic: don't fill the output window with just progress bars
						-- unless it's the only output (which might be confusing).
						-- But for `diff`, we want everything. `diff` doesn't print percentages.
						-- For `push`, we might want to hide the "Writing objects: 100%" lines from the persistent log?
						-- The original code kept everything. Let's stick to that but clean it.
						table.insert(all_output, clean_line(line))
					end
				end
			end

			collect_lines(stdout_lines)
			collect_lines(stderr_lines)

			cmd_output(command, all_output) -- open output for specific cmds
			vim.schedule(function()
				require("oz.git").refresh_buf()
			end)

			-- show output if failed operation
			if exit_code ~= 0 and output_callback then
				output_callback(all_output)
			-- Ensure callback is called for diff (exit_code 1 means diff found, usually)
			elseif command == "diff" and exit_code == 1 and output_callback then
				output_callback(all_output)
			end
		end,
	})

	return job_id
end

return M
