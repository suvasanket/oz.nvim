local M = {}
local util = require("oz.util")

local has_fidget = pcall(require, "fidget")
local fidget = has_fidget and require("fidget.progress") or nil

local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local current_spinner_frame = 1
local spinner_active = false
local spinner_timer = nil

local progress_percentage = 0
local progress_update_timer = nil
local progress_increment_value = 5

-- Clean ANSI codes and carriage returns from lines
local function clean_line(line)
	return line and line:gsub("\r", ""):gsub("\27%[%d+[mK]", "") or ""
end

-- Update spinner animation
local function update_spinner()
	if not spinner_active then
		return
	end
	current_spinner_frame = current_spinner_frame % #spinner_frames + 1
	return spinner_frames[current_spinner_frame]
end

-- Start progress increment timer
local function start_progress_updates()
	if progress_update_timer then
		return
	end

	-- Reset progress percentage
	progress_percentage = 0

	-- Start timer to increment progress
	progress_update_timer = vim.loop.new_timer()
	progress_update_timer:start(500, 500, function()
		if not spinner_active then
			if progress_update_timer then
				progress_update_timer:stop()
				progress_update_timer:close()
				progress_update_timer = nil
			end
			return
		end

		-- Increment progress but cap at 95% (save 100% for completion)
		if progress_percentage < 95 then
			progress_percentage = progress_percentage + progress_increment_value

			-- Update fidget progress
			if fidget and M.progress_handle then
				vim.schedule(function()
					M.progress_handle:report({
						percentage = progress_percentage,
						message = "In progress...",
					})
				end)
			end
		end
	end)
end

-- Start spinner
local function start_spinner(title)
	spinner_active = true
	if fidget then
		M.progress_handle = fidget.handle.create({
			title = title,
			message = "In progress...",
			lsp_client = { name = "oz_git" },
			percentage = 0,
		})
	else
		-- Start spinner timer for echo area
		spinner_timer = vim.loop.new_timer()
		spinner_timer:start(0, 100, function()
			if spinner_active then
				local spinner = update_spinner()
				vim.schedule(function()
					vim.api.nvim_echo(
						{ { spinner, "Comment" }, { " " .. title .. " (" .. progress_percentage .. "%)" } },
						false,
						{}
					)
				end)
			else
				spinner_timer:stop()
			end
		end)
	end

	-- Start progress updates
	start_progress_updates()
end

-- Stop spinner
local function stop_spinner(code)
	spinner_active = false

	-- Stop progress timer
	if progress_update_timer then
		progress_update_timer:stop()
		progress_update_timer:close()
		progress_update_timer = nil
	end

	if code == 0 then
		if fidget and M.progress_handle then
			M.progress_handle:report({
				message = "Completed successfully",
				percentage = 100,
			})
			M.progress_handle:finish()
			M.progress_handle = nil
		end
	else
		if fidget and M.progress_handle then
			M.progress_handle:report({
				message = "Failed!",
			})
			M.progress_handle:cancel()
			M.progress_handle = nil
		end
	end

	if spinner_timer then
		spinner_timer:stop()
		spinner_timer:close()
		spinner_timer = nil
	end

	vim.api.nvim_echo({ { "" } }, false, {})
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

	progress_percentage = 0

	start_spinner(title .. " in progress... ")

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

					if fidget and M.progress_handle then
						M.progress_handle:report({
							message = "In progress...",
						})
					end
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

					-- Update fidget message with latest error
					if fidget and M.progress_handle then
						M.progress_handle:report({
							message = "In progress...",
						})
					end
				end
			end
		end,
		on_exit = function(_, exit_code)
			stop_spinner(exit_code)
			cmd_output(command, all_output) -- open output for specific cmds
			vim.schedule(function()
				require("oz.git").refresh_buf()
			end)

			if exit_code == 0 then
				if fidget then
					-- Final progress report already done in stop_spinner
				else
					vim.api.nvim_echo(
						{ { " ", "healthSuccess" }, { title .. " completed successfully (100%)." } },
						false,
						{}
					)
				end
			else
				if output_callback then
					output_callback(all_output)
				else
					if fidget then
						fidget.notify(title .. " failed", "error")
						for _, line in ipairs(all_output) do
							fidget.notify(line, "error")
						end
					else
						vim.api.nvim_echo({ { "✗ " .. title .. " failed!", "healthError" } }, false, {})
						for _, line in ipairs(all_output) do
							vim.api.nvim_echo({ { line, "ErrorMsg" } }, false, {})
						end
					end
				end
			end
		end,
	})

	return job_id
end

return M
