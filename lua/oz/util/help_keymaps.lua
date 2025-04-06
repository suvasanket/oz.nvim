local M = {}
local key_help_win = nil
local key_help_buf = nil

local function filter_table(tbl, str)
	local result = {}
	local new_keys = {}
	for key, value in pairs(tbl) do
		if vim.startswith(key, str) then
			local new_key = key:sub(#str + 1)
			if new_key ~= "" then
				result[new_key] = value
				table.insert(new_keys, new_key)
			end
		end
	end
	return result, new_keys
end

local function set_keymaps(keymaps, arg_key)
	for _, key in pairs(keymaps) do
		key = key == "<Space>" and " " or key
		vim.keymap.set("n", key, function()
			vim.cmd("close")
			vim.cmd.normal(arg_key .. key)
		end, { nowait = true, buffer = key_help_buf, remap = false })
	end
end

function M.init(args)
	local bufnr = vim.api.nvim_get_current_buf()
	local modes = { "n", "v", "i", "t" }
	local sub_keys = {}
	local all_keymaps = {}

	-- First get all keymaps
	for _, mode in ipairs(modes) do
		local maps = vim.api.nvim_buf_get_keymap(bufnr, mode)
		for _, map in ipairs(maps) do
			local key = map.lhs:gsub(" ", "<Space>")
			local desc = map.desc or map.rhs
			if desc then
				desc = desc:gsub("<Cmd>", ""):gsub("<CR>", "")
			else
				if not args.no_empty then -- set a empty description. for default
					desc = "[No Info]"
				end
			end
			if not all_keymaps[key] and desc then -- don't add any no descriptive keys
				all_keymaps[key] = {
					modes = {},
					desc = desc,
				}
			end
			if all_keymaps[key] then -- check if all_keymaps[key] is not nil
				table.insert(all_keymaps[key].modes, mode)
			end
		end
	end

	if args.key then
		all_keymaps, sub_keys = filter_table(all_keymaps, args.key)
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
	if args.subtext then
		table.insert(keymaps, "")
		for _, i in ipairs(args.subtext) do
			table.insert(keymaps, " " .. i)
		end
	end

	if #keymaps == 0 then
		return
	end

	key_help_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(key_help_buf, 0, -1, false, keymaps)

	-- highlight
	vim.api.nvim_buf_call(key_help_buf, function()
		vim.cmd("syntax clear")
		vim.cmd("highlight BoldKey gui=bold guifg=#99BC85 cterm=bold")
		vim.cmd('syntax match BoldKey /"\\(.*\\)"/ contains=NONE')
		vim.cmd([[
        syntax match KeyMode /\[.*\]/
        highlight link KeyMode Comment
        ]])
		if has_headers then
			vim.cmd("highlight HeaderName gui=bold guifg=#DFD3C3 guibg=#2F2F2F cterm=bold")
			vim.cmd("highlight HeaderBlocks guifg=#2F2F2F ctermfg=green")
			vim.cmd("syntax match HeaderName /█.*█/ contains=HeaderBlocks")
			vim.cmd("syntax match HeaderBlocks /[██]/ contained")
		end
	end)

	-- floating window dimensions and position
	local fixed_width = 60
	local max_height = 15

	local max_width = 0
	for _, line in ipairs(keymaps) do
		max_width = math.max(max_width, vim.fn.strwidth(line))
	end

	local total_lines = vim.api.nvim_buf_line_count(key_help_buf)
	local height = math.min(total_lines, max_height)
	local width = (max_height > 100) and fixed_width or max_width + 2
	local row = vim.o.lines - height - 4
	local col = vim.o.columns

	local title = args.title or "Show Keymaps"
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "single",
		title = " " .. title .. " ",
		title_pos = "left",
	}
	key_help_win = vim.api.nvim_open_win(key_help_buf, true, win_opts)
	vim.api.nvim_buf_set_option(key_help_buf, "modifiable", false)
	vim.api.nvim_buf_set_keymap(key_help_buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(key_help_buf, "n", "<C-c>", "<cmd>close<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(key_help_buf, "n", "<Esc>", "<cmd>close<CR>", { noremap = true, silent = true })

	if #sub_keys > 0 then
		vim.fn.timer_start(100, function()
			set_keymaps(sub_keys, args.key)
		end)
	end
	return key_help_win, key_help_buf
end

return M
