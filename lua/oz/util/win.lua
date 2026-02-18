--- @class oz.util.win
local M = {}

local unique_ids = {}

--- Internal helper to create a window.
--- @param opts {win_type: string, buf_name: string, content: string[], callback: function}
--- @return integer win_id
---@return integer buf_id
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

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, opts.content or {})

	if opts.callback then
		opts.callback(buf_id, win_id)
	end
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })

	return win_id, buf_id
end

--- Create or reuse a window identified by a unique ID.
--- @param unique_id string
--- @param opts {buf_name: string, content: string[], reuse: boolean, win_type: string, callback: function}
--- @return integer win_id
--- @return integer buf_id
function M.create_win(unique_id, opts)
	local win_buf_id = unique_ids[unique_id]
	local reuse = opts.reuse

	-- if not reuse then remove the buffer only if it's not visible
	if not reuse and win_buf_id then
		if vim.api.nvim_buf_is_valid(win_buf_id.buf_id) then
			local wins = vim.fn.win_findbuf(win_buf_id.buf_id)
			if #wins == 0 then
				vim.api.nvim_buf_delete(win_buf_id.buf_id, { force = true })
			end
		end
	end

	-- if win_buf_id exist then re-use that else create one
	if reuse and win_buf_id then
		local win_id = win_buf_id.win_id
		if vim.api.nvim_win_is_valid(win_id) then
			vim.api.nvim_set_current_win(win_id)
			local buf_id = vim.api.nvim_win_get_buf(win_id)
			if opts.content and vim.api.nvim_buf_is_valid(buf_id) then
				vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
				vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, opts.content)
				vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
			end

			if opts.callback then
				opts.callback(buf_id, win_id)
			end

			-- The callback might have changed the buffer (e.g. terminal)
			local actual_buf = vim.api.nvim_win_get_buf(win_id)
			unique_ids[unique_id] = { win_id = win_id, buf_id = actual_buf }

			return win_id, actual_buf
		end
	end

	local win, buf = create_win_util(opts)
	-- Re-fetch buffer in case callback changed it
	local actual_buf = vim.api.nvim_win_get_buf(win)

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		callback = function()
			if unique_ids[unique_id] and unique_ids[unique_id].win_id == win then
				unique_ids[unique_id] = nil
			end
		end,
	})
	unique_ids[unique_id] = { win_id = win, buf_id = actual_buf }
	return win, actual_buf
end

--- Create a floating window centered in the editor.
--- @param opts {content: string[], title: string, width?: number, height?: number, footer?: string}
--- @return integer win_id
--- @return integer buf_id
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

	-- Ensure transparent highlight group exists
	vim.api.nvim_set_hl(0, "ozTransparent", { bg = "NONE", ctermbg = "NONE" })


	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = { " ", " ", " ", " ", " ", " ", " ", " " },
		title = " " .. title .. " ",
		title_pos = "center",
		footer = opts.footer,
		footer_pos = "center",
	}

	local win_id = vim.api.nvim_open_win(buf_id, true, win_opts)
	vim.api.nvim_win_set_option(win_id, "winblend", 20)
	vim.api.nvim_win_set_option(
		win_id,
		"winhighlight",
		"NormalFloat:StatusLine,FloatBorder:ozTransparent,FloatTitle:StatusLine"
	)

	return win_id, buf_id
end

--- Create a bottom overlay window (Magit/Neogit style).
--- @param opts {content: string[], title: string, height?: number}
--- @return integer win_id
--- @return integer buf_id
function M.create_bottom_overlay(opts)
	local content = opts.content or {}
	local height = opts.height or #content
	local title = opts.title or "Menu"
	local width = vim.o.columns

	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)

	vim.api.nvim_set_hl(0, "ozTransparent", { bg = "NONE", ctermbg = "NONE" })
	local row = vim.o.lines - height - 2 -- -2 for statusline and cmdline space roughly

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = 0,
		style = "minimal",
		border = { " ", " ", "", "", "", "", "", "" },
		title = ("  %s  "):format(title),
		title_pos = "left",
		zindex = 1000,
	}

	local win_id = vim.api.nvim_open_win(buf_id, true, win_opts)

	-- Set local options for "minimal" feel
	vim.api.nvim_win_set_option(win_id, "winblend", 2)
	vim.api.nvim_win_set_option(
		win_id,
		"winhighlight",
		"NormalFloat:StatusLine,FloatBorder:ozTransparent,FloatTitle:StatusLine"
	)

	return win_id, buf_id
end

return M
