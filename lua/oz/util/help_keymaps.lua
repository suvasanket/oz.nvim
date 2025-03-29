local M = {}

function M.init(args)
	local bufnr = vim.api.nvim_get_current_buf()
	local modes = { "n", "v", "i", "t" }

	-- First get all keymaps
	local all_keymaps = {}
	for _, mode in ipairs(modes) do
		local maps = vim.api.nvim_buf_get_keymap(bufnr, mode)
		for _, map in ipairs(maps) do
			local key = map.lhs:gsub(" ", "<Space>")
			local desc = map.desc or map.rhs
			if desc then
				desc = desc:gsub("<Cmd>", ""):gsub("<CR>", "")
			else
				desc = "[No Info]"
			end
			if not all_keymaps[key] then
				all_keymaps[key] = {
					modes = {},
					desc = desc,
				}
			end
			table.insert(all_keymaps[key].modes, mode)
		end
	end

	local keymaps = {}
	local has_headers = args and args.header_name and not vim.tbl_isempty(args.header_name)

	if has_headers then
		-- Process header groups
		local grouped_keymaps = {}
		for header_name, keys in pairs(args.header_name) do
			for _, key in ipairs(keys) do
				if all_keymaps[key] then
					if not grouped_keymaps[header_name] then
						grouped_keymaps[header_name] = {}
					end
					grouped_keymaps[header_name][key] = all_keymaps[key]
					all_keymaps[key] = nil -- Remove from regular keymaps
				end
			end
		end

		-- Add grouped keymaps with their headers
		for header_name, keys in pairs(grouped_keymaps) do
			-- Add header (no newline before first header)
			if #keymaps > 0 then
				table.insert(keymaps, "")
			end
			table.insert(keymaps, " █" .. header_name .. "█")

			-- Add each key in this group
			local sorted_keys = {}
			for key in pairs(keys) do
				table.insert(sorted_keys, key)
			end
			table.sort(sorted_keys)

			for _, key in ipairs(sorted_keys) do
				local data = keys[key]
				table.sort(data.modes)
				local modes_l = "[" .. table.concat(data.modes, ", ") .. "]"
				local line = string.format(" %s  %s 󱦰 %s", modes_l, '"' .. key .. '"', data.desc)
				table.insert(keymaps, line)
			end
		end

		-- Add remaining keymaps under "Other Mappings" if any exist
		if not vim.tbl_isempty(all_keymaps) then
			table.insert(keymaps, "")
			table.insert(keymaps, " █Other Mappings█")

			local sorted_keys = {}
			for key in pairs(all_keymaps) do
				table.insert(sorted_keys, key)
			end
			table.sort(sorted_keys)

			for _, key in ipairs(sorted_keys) do
				local data = all_keymaps[key]
				table.sort(data.modes)
				local modes_l = "[" .. table.concat(data.modes, ", ") .. "]"
				local line = string.format(" %s  %s 󱦰 %s", modes_l, '"' .. key .. '"', data.desc)
				table.insert(keymaps, line)
			end
		end
	else
		-- No headers - just add all keymaps sorted
		local sorted_keys = {}
		for key in pairs(all_keymaps) do
			table.insert(sorted_keys, key)
		end
		table.sort(sorted_keys)

		for _, key in ipairs(sorted_keys) do
			local data = all_keymaps[key]
			table.sort(data.modes)
			local modes_l = "[" .. table.concat(data.modes, ", ") .. "]"
			local line = string.format(" %s  %s 󱦰 %s", modes_l, '"' .. key .. '"', data.desc)
			table.insert(keymaps, line)
		end
	end

	-- Add subtext (footer)
	table.insert(keymaps, "")
	if args and args.subtext then
		for _, i in ipairs(args.subtext) do
			table.insert(keymaps, " " .. i)
		end
	end
	table.insert(keymaps, " press 'q' to close this window.")

	if #keymaps == 0 then
		return
	end

	local temp_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, keymaps)

	-- highlight
	vim.api.nvim_buf_call(temp_buf, function()
		vim.cmd("syntax clear")
		vim.cmd("highlight BoldKey gui=bold guifg=#99BC85 cterm=bold")
		vim.cmd('syntax match BoldKey /"\\(.*\\)"/ contains=NONE')
		vim.cmd([[
        syntax match KeyMode /\[.*\]/
        highlight link KeyMode Comment
        ]])
		if has_headers then
			vim.cmd("highlight HeaderName gui=bold guifg=#C5BAFF guibg=#2F2F2F cterm=bold")
			vim.cmd("highlight HeaderBlocks guifg=#2F2F2F ctermfg=green")
			vim.cmd("syntax match HeaderName /█.*█/ contains=HeaderBlocks")
			vim.cmd("syntax match HeaderBlocks /[██]/ contained")
		end
	end)

	-- floating window dimensions and position
	local fixed_width = 55
	local max_height = 15

	local wrapped_lines = {}
	for _, line in ipairs(keymaps) do
		for i = 1, #line, fixed_width do
			table.insert(wrapped_lines, line:sub(i, i + fixed_width - 1))
		end
	end
	local max_width = 0
	for _, line in ipairs(keymaps) do
		max_width = math.max(max_width, vim.fn.strwidth(line))
	end

	local height = math.min(#wrapped_lines, max_height)
	local width = (max_height > 100) and fixed_width or max_width + 2
	local row = vim.o.lines - height - 4
	local col = vim.o.columns - fixed_width - 2

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "single",
	}
	local temp_win = vim.api.nvim_open_win(temp_buf, true, win_opts)
	vim.api.nvim_buf_set_option(temp_buf, "modifiable", false)
	vim.api.nvim_buf_set_keymap(temp_buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
	return temp_win, temp_buf
end

return M
