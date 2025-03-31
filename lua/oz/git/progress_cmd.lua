local M = {}

-- Check if fidget is available
local has_fidget = pcall(require, "fidget")
local fidget = has_fidget and require("fidget") or nil

-- Spinner frames
local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local current_spinner_frame = 1

-- Update spinner animation
local function update_spinner()
	current_spinner_frame = current_spinner_frame % #spinner_frames + 1
	return spinner_frames[current_spinner_frame]
end

-- Show progress message
local function show_progress(title, message, percentage)
	if fidget then
		if not M.progress_notification then
			M.progress_notification = fidget.progress({
				title = title,
				lsp_client = { name = "git" },
			})
		end
		M.progress_notification:report({
			message = message,
			percentage = percentage,
		})
	else
		local spinner = update_spinner()
		local progress_bar = percentage and string.format(" [%3d%%]", percentage) or ""
		vim.api.nvim_echo({
			{ spinner, "Comment" },
			{ string.format(" %s%s: %s", title, progress_bar, message or "") },
		}, false, {})
	end
end

-- Clear progress display
local function clear_progress()
	if fidget and M.progress_notification then
		M.progress_notification:finish()
		M.progress_notification = nil
	else
		-- Clear the echo area
		vim.api.nvim_echo({ { "" } }, false, {})
	end
end

-- Parse git progress percentage from line
local function parse_progress(line)
	local percentage = line:match("(%d+)%%")
	return percentage and tonumber(percentage) or nil
end

-- Main git async function
function M.run_git_with_progress(command, args, MY_FUNC)
	-- Validate command
	local valid_commands = {
		push = true,
		pull = true,
		fetch = true,
	}

	if not valid_commands[command] then
		if fidget then
			fidget.notify("Invalid git command: " .. command, "error")
		else
			vim.api.nvim_echo({ { "Error: Invalid git command: " .. command, "ErrorMsg" } }, true, {})
		end
		return
	end

	-- Prepare command
	local cmd = table.concat({ "git", command, unpack(args or {}) }, " ")
	local title = "git " .. command:sub(1, 1) .. command:sub(2)

	-- Buffer to collect all output lines
	local all_output = {}

	-- Start progress
	show_progress(title, "Starting...")

	-- Execute command
	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				if line ~= "" then
					local clean_line = line:gsub("\r", ""):gsub("\27%[%d+[mK]", "")
					table.insert(all_output, clean_line)
					local percentage = parse_progress(clean_line)
					show_progress(title, clean_line, percentage)
				end
			end
		end,
		on_stderr = function(_, data, _)
			for _, line in ipairs(data) do
				if line ~= "" then
					local clean_line = line:gsub("\r", ""):gsub("\27%[%d+[mK]", "")
					table.insert(all_output, clean_line)
					show_progress(title, clean_line)
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			if exit_code == 0 then
				clear_progress()
				if fidget then
					fidget.notify(title .. " completed", "success")
				else
					vim.api.nvim_echo(
						{ { " ", "healthSuccess" }, { title .. " completed successfully." } },
						false,
						{}
					)
				end
			else
				clear_progress()
				if fidget then
					fidget.notify(title .. " failed", "error")
					for _, line in ipairs(all_output) do
						fidget.notify(line, "error")
					end
				else
					if MY_FUNC then
						MY_FUNC(all_output)
					else
						vim.api.nvim_echo(
							{ { "󱎘 ", "healthError" }, { title .. " failed!", "ErrorMsg" } },
							false,
							{}
						)
					end
				end
			end
		end,
	})
end

return M
