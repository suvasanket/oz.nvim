local M = {}

local unique_ids = {}

function M.create_win(opts)
	local buf_id = vim.api.nvim_create_buf(false, true)
	vim.cmd(("%s new"):format(opts.win_type)) -- hor, vert, tab
	local temp_buf = vim.api.nvim_get_current_buf()
	local win_id = vim.api.nvim_get_current_win()

	vim.api.nvim_win_set_buf(win_id, buf_id)
	vim.api.nvim_buf_delete(temp_buf, { force = true })
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, opts.lines)

	opts.callback(buf_id, win_id)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)

	return win_id, buf_id
end

function M.open_win(unique_id, opts)
	local win_buf_id = unique_ids[unique_id]
	if win_buf_id then
		local win_id = win_buf_id.win_id
		local buf_id = win_buf_id.buf_id
		if vim.api.nvim_win_is_valid(win_id) or vim.api.nvim_buf_is_valid(buf_id) then
			if opts.lines then
				vim.api.nvim_set_current_win(win_id)
				vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
				vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, opts.lines)
				vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
			end
		end
	else
		local win, buf = M.create_win(opts)
		vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
			buffer = buf,
			callback = function()
				unique_ids[unique_id] = nil
			end,
		})
		unique_ids[unique_id] = { win_id = win, buf_id = buf }
	end
end

return M
