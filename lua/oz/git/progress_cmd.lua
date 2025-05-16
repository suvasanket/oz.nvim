local M = {}
local util = require("oz.util")
local progress = require("oz.util.progress")

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

	local u_id = util.generate_unique_id()
	progress.start_progress(u_id, { title = title, fidget_lsp = "oz_git" })

	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line and line ~= "" then
					local clean_output = clean_line(line)
					all_output[#all_output + 1] = clean_output
				end
			end
		end,
		on_stderr = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line and line ~= "" then
					local clean_output = clean_line(line)
					all_output[#all_output + 1] = clean_output
					-- table.insert(all_output, 1, clean_output)
				end
			end
		end,
		on_exit = function(_, exit_code)
			progress.stop_progress(u_id, { exit_code = exit_code, title = title })

			cmd_output(command, all_output) -- open output for specific cmds
			vim.schedule(function()
				require("oz.git").refresh_buf()
			end)

            -- show output if failed operation
			if exit_code ~= 0 and output_callback then
				output_callback(all_output)
			end
		end,
	})

	return job_id
end

return M
