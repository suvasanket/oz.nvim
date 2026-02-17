--- @class oz.util.editor_util
local M = {}

--- Get the current visual selection as a string or table of lines.
--- @param tbl_fmt? boolean Whether to return a table of lines instead of a joined string.
--- @return string|string[] The visual selection.
function M.get_visual_selection(tbl_fmt)
	local start_pos = vim.api.nvim_buf_get_mark(0, "<")
	local end_pos = vim.api.nvim_buf_get_mark(0, ">")

	local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)

	if start_pos[1] == end_pos[1] then
		local line = lines[1]
		local selected = line:sub(start_pos[2] + 1, end_pos[2])
		return tbl_fmt and { selected } or selected
	end

	lines[1] = lines[1]:sub(start_pos[2] + 1)
	if #lines > 1 then
		lines[#lines] = lines[#lines]:sub(1, end_pos[2])
	end

	return tbl_fmt and lines or table.concat(lines, "\n")
end

--- Open a path in an existing non-relative window if available, otherwise open in a split.
--- @param path string The file path to open.
function M.open_in_split(path)
	local current_win = vim.api.nvim_get_current_win()
	local wins = vim.api.nvim_tabpage_list_wins(0)

	for _, win in ipairs(wins) do
		if win ~= current_win then
			local config = vim.api.nvim_win_get_config(win)
			if config.relative == "" then
				vim.api.nvim_set_current_win(win)
				vim.cmd.edit(vim.fn.fnameescape(path))
				return
			end
		end
	end

	vim.cmd("aboveleft split " .. vim.fn.fnameescape(path))
end

return M
