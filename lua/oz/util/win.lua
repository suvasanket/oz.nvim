local M = {}

local unique_ids = {}

--- helper
---@param opts {win_type: string, buf_name: string, content: table, callback: function}
---@return integer
---@return integer
local function create_win_util(opts)
	local buf_id = vim.api.nvim_create_buf(false, true)
	if opts.buf_name then
		local existing = vim.fn.bufnr("^" .. opts.buf_name .. "$")
		if existing ~= -1 and existing ~= buf_id then
			vim.api.nvim_buf_delete(existing, { force = true })
		end
		vim.api.nvim_buf_set_name(buf_id, opts.buf_name)
	end

	local win_id
	if opts.win_type == "current" then
		win_id = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win_id, buf_id)
	else
		vim.cmd(("%s new"):format(opts.win_type)) -- hor, vert, tab
		local temp_buf = vim.api.nvim_get_current_buf()
		win_id = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win_id, buf_id)
		vim.api.nvim_buf_delete(temp_buf, { force = true })
	end

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, opts.content)

	opts.callback(buf_id, win_id)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)

	return win_id, buf_id
end

--- create win
---@param unique_id string
---@param opts {buf_name: string, content: table, reuse: boolean, win_type: string, callback: function}
function M.create_win(unique_id, opts)
	local win_buf_id = unique_ids[unique_id]
	local reuse = opts.reuse

	-- if not reuse then remove the buffer
	if not reuse and win_buf_id then
		if vim.api.nvim_buf_is_valid(win_buf_id.buf_id) then
			vim.api.nvim_buf_delete(win_buf_id.buf_id, { force = true })
		end
	end

	-- if win_buf_id exist then re-use that else create one
	if reuse and win_buf_id then
		local win_id = win_buf_id.win_id
		local buf_id = win_buf_id.buf_id
		if vim.api.nvim_win_is_valid(win_id) or vim.api.nvim_buf_is_valid(buf_id) then
			if opts.content then
				vim.api.nvim_set_current_win(win_id)
				vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
				vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, opts.content)
				vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
			end
		end
	else
		local win, buf = create_win_util(opts)
		vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
			buffer = buf,
			callback = function()
				unique_ids[unique_id] = nil
			end,
		})
		unique_ids[unique_id] = { win_id = win, buf_id = buf }
	end
end

--- Create a floating window
---@param opts {content: string[], title: string, width: number|nil, height: number|nil, footer: string|nil}
---@return integer win_id
---@return integer buf_id
function M.create_floating_window(opts)
	local content = opts.content or {}
	local width = opts.width or 60
	local height = opts.height or #content
	local title = opts.title or "Menu"

	-- Calculate centered position
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
		footer = opts.footer,
		footer_pos = "center",
	}

	local win_id = vim.api.nvim_open_win(buf_id, true, win_opts)

	return win_id, buf_id
end

--- Create a bottom overlay window (Magit/Neogit style)
---@param opts {content: string[], title: string, height: number|nil}
---@return integer win_id
---@return integer buf_id
function M.create_bottom_overlay(opts)
	local content = opts.content or {}
	local height = opts.height or #content
	local title = opts.title or "Menu"
	local width = vim.o.columns

	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)

	-- We want a window at the bottom, full width.
	-- We use a border to show the title, but we can customize the characters to look like a top-only line if needed,
	-- or just use "single" which is clean.
	-- To make it "from the bottom", row should be lines - height.
	local row = vim.o.lines - height - 2 -- -2 for statusline and cmdline space roughly

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = 0,
		style = "minimal",
		border = { "─", "─", " ", " ", " ", " ", " ", " " }, -- Top border only
		title = " " .. title .. " ",
		title_pos = "left",
	}

	local win_id = vim.api.nvim_open_win(buf_id, true, win_opts)

	-- Set local options for "minimal" feel
	vim.api.nvim_win_set_option(win_id, "winblend", 0)

	return win_id, buf_id
end

return M
