local M = {}
local key_help_win = nil
local key_help_buf = nil

--- helper: filter keys from user provided 'key'
---@param tbl table
---@param str string
---@return table
---@return table
local function filter_table(tbl, str)
	local result = {}
	local new_keys = {}
	for key, value in pairs(tbl) do
		if vim.startswith(key, str) then
			local new_key = key:sub(#str + 1)
			if new_key ~= "" then
				result[new_key] = value
				new_key = new_key:gsub("<Space>", " ")
				table.insert(new_keys, new_key)
			end
		end
	end
	return result, new_keys
end

--- get header str fmt
---@param str string
local function header_fmt(str)
	return string.format("█%s█", str)
end

--- show mappings
---@param args {title: string, no_empty: boolean, key: string, group: table<string, string[]>, subtext: string[], parent_buf: integer|nil, sub_help_buf: boolean}
---@return integer|nil
---@return integer|nil
function M.show_maps(args)
	-- Capture the starting window immediately for robust focus switching later
	local start_win = vim.api.nvim_get_current_win()
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
	local has_headers = args and args.group and not vim.tbl_isempty(args.group)

	if has_headers then
		-- Process header groups
		local grouped_keymaps = {}
		for header_name, keys in pairs(args.group) do
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
			table.insert(keymaps, header_fmt(header_name))

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
			table.insert(keymaps, header_fmt("unspecified"))

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

	-- highlight --
	vim.api.nvim_buf_call(key_help_buf, function()
		vim.cmd("syntax clear")
		vim.cmd("highlight BoldKey gui=bold guifg=#99BC85 cterm=bold")
		vim.cmd('syntax match BoldKey /"\\(.*\\)"/ contains=NONE')
		vim.cmd([[
        syntax match Comment /\[.*\]/
        syntax match @keyword /<.*>/
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

	local title_str = args.title or "All keymaps"
	local footer_str = args.sub_help_buf and "ctrl-c/esc cancel" or "<C-f> find heading"

	-- win options --
	local win_opts = {}

	if args.sub_help_buf then
		win_opts = {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
			title = " " .. title_str .. " ",
			title_pos = "left",
			footer = " " .. footer_str .. " ",
			footer_pos = "right",
		}
	else
		-- Split configuration
		win_opts = {
			split = "below",
			win = 0, -- Split relative to current window
			height = height,
			style = "minimal", -- This implicitly handles number, relativenumber, cursorline, etc.
		}
	end

	key_help_win = vim.api.nvim_open_win(key_help_buf, true, win_opts)
	vim.api.nvim_buf_set_option(key_help_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(key_help_buf, "buftype", "nofile")

	-- If not floating, ensure "bare" options are strictly enforced on the split window
	if not args.sub_help_buf then
		local set_opt = vim.api.nvim_win_set_option
		set_opt(key_help_win, "wrap", false)
		set_opt(key_help_win, "foldcolumn", "0")
		-- These are technically covered by style="minimal", but explicitly setting them
		-- ensures no plugins (like line number togglers) override the minimal style on Enter.
		set_opt(key_help_win, "signcolumn", "no")
		set_opt(key_help_win, "number", false)
		set_opt(key_help_win, "relativenumber", false)
	end

	--- keymaps ---
	local function close_and_return()
		pcall(vim.api.nvim_win_close, 0, true)

		if args.parent_buf and vim.api.nvim_buf_is_valid(args.parent_buf) then
			-- Optimization: check if start_win is valid and matches parent_buf first
			if
				start_win
				and vim.api.nvim_win_is_valid(start_win)
				and vim.api.nvim_win_get_buf(start_win) == args.parent_buf
			then
				vim.api.nvim_set_current_win(start_win)
			else
				-- Fallback lookup
				local parent_wins = vim.fn.win_findbuf(args.parent_buf)
				if #parent_wins > 0 then
					vim.api.nvim_set_current_win(parent_wins[1])
				else
					vim.api.nvim_set_current_buf(args.parent_buf)
				end
			end
		end
	end

	vim.keymap.set("n", "q", close_and_return, { buffer = key_help_buf, noremap = true, silent = true })
	vim.keymap.set("n", "<C-c>", close_and_return, { buffer = key_help_buf, noremap = true, silent = true })
	vim.keymap.set("n", "<esc>", close_and_return, { buffer = key_help_buf, noremap = true, silent = true })

	if not args.sub_help_buf then
		vim.keymap.set("n", "<C-f>", function()
			local keys = vim.tbl_keys(args.group)
			vim.ui.select(keys, {
				prompt = "select heading",
				format_item = function(key)
					return key
				end,
			}, function(choice)
				if not choice then
					return
				end

				local pattern = header_fmt(choice)
				local pos = vim.fn.searchpos("\\V" .. pattern, "w")

				if pos[1] ~= 0 then
					vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] - 1 })
				end
			end)
		end, { buffer = key_help_buf, noremap = true, silent = true })
	end

	-- --
	if #sub_keys > 0 then
		-- Refactored efficiency: Directly focus the original window using API
		if vim.api.nvim_win_is_valid(start_win) then
			vim.api.nvim_set_current_win(start_win)
		end

		vim.fn.timer_start(10, function()
			local ok, char = pcall(vim.fn.getchar)
			if ok then
				char = vim.fn.nr2char(char)
				local full_sequence = args.key .. char

				if char then
					if vim.tbl_contains(sub_keys, char) then
						vim.api.nvim_feedkeys(full_sequence, "mt", false)
					end
				end
			end
			if key_help_win and vim.api.nvim_win_is_valid(key_help_win) then -- close win
				vim.api.nvim_win_close(key_help_win, true)
			end
		end)
	end
	return key_help_win, key_help_buf
end

return M
