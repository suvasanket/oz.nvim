--- @class oz.util.progress
local M = {}
local has_fidget = pcall(require, "fidget")
local fidget = has_fidget and require("fidget.progress") or nil
M.progress_tbl = {}

local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local current_spinner_frame = 1
local spinner_active = false

local progress_percentage = 0
local progress_update_timer = nil
local progress_increment_value = 5

--- Update spinner animation.
--- @return string|nil The next frame of the spinner.
local function update_spinner()
	if not spinner_active then
		return
	end
	current_spinner_frame = current_spinner_frame % #spinner_frames + 1
	return spinner_frames[current_spinner_frame]
end

--- Start progress increment timer.
--- @param unique_id string The unique ID for this progress session.
local function start_spinner_updates(unique_id)
	if progress_update_timer then
		return
	end

	-- WTF: for some shit reason i can't access M.progress_tbl items by passing index
	local fidget_handle
	for k, v in pairs(M.progress_tbl) do
		if k == unique_id then
			fidget_handle = v
		end
	end

	-- Reset progress percentage
	progress_percentage = 0

	-- Start timer to increment progress
	progress_update_timer = vim.loop.new_timer()
	if progress_update_timer then
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
				if fidget and fidget_handle then
					vim.schedule(function()
						fidget_handle:report({
							percentage = progress_percentage,
							message = "in progress...",
						})
					end)
				end
			end
		end)
	end
end

--- Start spinner or fidget progress.
--- @param unique_id string
---@param opts {title: string, fidget_lsp?: string, message?: string, manual?: boolean}
function M.start_progress(unique_id, opts)
	local msg = opts.message or "in progress..."
	spinner_active = true
	if fidget then
		unique_id = unique_id .. "_fidget_handle"
		M.progress_tbl[unique_id] = fidget.handle.create({
			title = opts.title,
			message = msg,
			lsp_client = { name = opts.fidget_lsp or "oz" },
			percentage = 0,
		})
	else
		-- Start spinner timer for echo area
		local spiner_timer = vim.loop.new_timer()
		if spiner_timer then
			M.progress_tbl[unique_id .. "_spinner_handle"] = spiner_timer

			spiner_timer:start(0, 100, function()
				if spinner_active then
					local spinner = update_spinner()
					vim.schedule(function()
						vim.api.nvim_echo({
							{ spinner, "@constant" },
							{ (" %s %s (%s%%)"):format(opts.title, msg, progress_percentage) },
						}, false, {})
					end)
				else
					spiner_timer:stop()
				end
			end)
		end
	end

	-- Start progress updates
	if not opts.manual then
		start_spinner_updates(unique_id)
	end
end

--- Update progress manually.
--- @param unique_id string
--- @param percentage number
--- @param message string
function M.update_progress(unique_id, percentage, message)
	progress_percentage = percentage

	local fidget_handle = M.progress_tbl[unique_id .. "_fidget_handle"]
	if fidget and fidget_handle then
		fidget_handle:report({
			percentage = percentage,
			message = message,
		})
	end
end

--- Stop spinner and show completion message.
--- @param unique_id string
---@param opts {title: string, exit_code: integer, message?: string[]}
function M.stop_progress(unique_id, opts)
	local msg = opts.message and (opts.exit_code == 0 and opts.message[1] or opts.message[2])
		or (opts.exit_code == 0 and "completed successfully" or "failed")
	spinner_active = false

	local fidget_handle = M.progress_tbl[unique_id .. "_fidget_handle"]
	local spinner_handle = M.progress_tbl[unique_id .. "_spinner_handle"]

	-- Stop progress timer
	if progress_update_timer then
		progress_update_timer:stop()
		progress_update_timer:close()
		progress_update_timer = nil
	end

	if opts.exit_code == 0 then
		if fidget and fidget_handle then
			fidget_handle:report({
				message = msg,
				percentage = 100,
			})
			fidget_handle:finish()
			fidget_handle = nil
		else
			vim.api.nvim_echo({
				{ " ", "healthSuccess" },
				{ (" %s %s (100%%)"):format(opts.title, msg) },
			}, false, {})
		end
	else
		if fidget and fidget_handle then
			fidget_handle:report({
				message = msg,
			})
			fidget_handle:cancel()
			fidget_handle = nil
		else
			vim.api.nvim_echo({
				{ "✗ ", "healthError" },
				{ (" %s %s (%s%%)"):format(opts.title, msg, progress_percentage) },
			}, false, {})
		end
	end

	if spinner_handle then
		spinner_handle:stop()
		spinner_handle:close()
		spinner_handle = nil
	end
end

return M
