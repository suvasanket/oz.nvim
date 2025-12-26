local M = {}
local win_util = require("oz.util.win")

-- Module-level tracking for singleton behavior
local key_help_win = nil
local key_help_buf = nil
local menu_win = nil
local menu_buf = nil
local menu_prev_win = nil
local original_guicursor = nil

-- Internal helper: Close existing window and buffer
local function close_window()
	if key_help_win and vim.api.nvim_win_is_valid(key_help_win) then
		vim.api.nvim_win_close(key_help_win, true)
	end
	key_help_win = nil

	if key_help_buf and vim.api.nvim_buf_is_valid(key_help_buf) then
		vim.api.nvim_buf_delete(key_help_buf, { force = true })
	end
	key_help_buf = nil
end

local function close_menu()
	if menu_win and vim.api.nvim_win_is_valid(menu_win) then
		vim.api.nvim_win_close(menu_win, true)
	end
	menu_win = nil
	if menu_buf and vim.api.nvim_buf_is_valid(menu_buf) then
		vim.api.nvim_buf_delete(menu_buf, { force = true })
	end
	menu_buf = nil

	if original_guicursor then
		vim.opt.guicursor = original_guicursor
		original_guicursor = nil
	end

	if menu_prev_win and vim.api.nvim_win_is_valid(menu_prev_win) then
		vim.api.nvim_set_current_win(menu_prev_win)
		menu_prev_win = nil
	end
end

-- helper: filter keys from user provided 'key'
---@param tbl table
---@param str string
---@return table
---@return table
local function filter_table(tbl, str)
	local result = {}
	local new_keys = {}
	local len = #str
	for key, value in pairs(tbl) do
		if key:sub(1, len) == str then
			local new_key = key:sub(len + 1)
			if new_key ~= "" then
				result[new_key] = value
				new_key = new_key:gsub("<Space>", " ")
				table.insert(new_keys, new_key)
			end
		end
	end
	return result, new_keys
end

--- show mappings
---@param args {title: string, key: string, group: table<string, string[]>}
function M.show_maps(args)
	-- 1. Enforce Singleton: Close any existing instances
	close_window()
	close_menu()

	menu_prev_win = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()
	local modes = { "n", "v", "i", "t" }
	local all_keymaps = {}

	-- 2. Gather Keymaps Efficiently
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

			if desc then
				if not all_keymaps[key] then
					all_keymaps[key] = { modes = {}, desc = desc }
				end
				table.insert(all_keymaps[key].modes, mode)
			end
		end
	end

	if args.key then
		all_keymaps, _ = filter_table(all_keymaps, args.key)
	end

	-- 3. Organize Content
	local groups = {}
	local used_keys = {}

	-- Process defined groups
	if args.group then
		local group_names = vim.tbl_keys(args.group)
		table.sort(group_names)

		for _, name in ipairs(group_names) do
			local keys = args.group[name]
			local group_items = {}
			for _, k in ipairs(keys) do
				local key_norm = k:gsub(" ", "<Space>")
				if all_keymaps[key_norm] then
					used_keys[key_norm] = true
					table.insert(group_items, { key = key_norm, data = all_keymaps[key_norm] })
				end
			end
			if #group_items > 0 then
				table.insert(groups, { title = name, items = group_items })
			end
		end
	end

	-- Process remaining keys (General)
	local general_items = {}
	local sorted_keys = vim.tbl_keys(all_keymaps)
	table.sort(sorted_keys)

	for _, key in ipairs(sorted_keys) do
		if not used_keys[key] then
			table.insert(general_items, { key = key, data = all_keymaps[key] })
		end
	end

	if #general_items > 0 then
		table.insert(groups, { title = args.group and "General" or nil, items = general_items })
	end

	if #groups == 0 then
		vim.api.nvim_echo({ { "No keymaps found.", "WarningMsg" } }, false, {})
		return
	end

	-- 4. Calculate Layout
	-- First pass: format strings and find max width
	local max_width = 0
	for _, group in ipairs(groups) do
		for _, item in ipairs(group.items) do
			table.sort(item.data.modes)
			local modes_l = "[" .. table.concat(item.data.modes, ",") .. "]"
			-- format: " [modes] key  desc"
			item.text = string.format(" %-6s %s  %s", modes_l, item.key, item.data.desc)
			if #item.text > max_width then
				max_width = #item.text
			end
		end
	end

	local col_width = max_width + 2
	local win_width = vim.o.columns
	local num_cols = math.floor(win_width / col_width)
	if num_cols < 1 then
		num_cols = 1
	end

	-- Build Render Lines
	local render_lines = {}
	for _, group in ipairs(groups) do
		if group.title then
			table.insert(render_lines, string.format("%%#HeaderName#%s", group.title))
		end

		local items = group.items
		local num_rows = math.ceil(#items / num_cols)

		for r = 1, num_rows do
			local line_parts = {}
			for c = 1, num_cols do
				local idx = (c - 1) * num_rows + r
				if idx <= #items then
					local entry = items[idx]
					local padding = string.rep(" ", col_width - #entry.text)
					table.insert(line_parts, entry.text .. padding)
				end
			end
			table.insert(render_lines, table.concat(line_parts))
		end
		-- Add spacer if not last group
		table.insert(render_lines, "")
	end

	-- Remove trailing empty line
	if render_lines[#render_lines] == "" then
		table.remove(render_lines)
	end

	-- 5. Create Window with Height Constraint
	local total_lines = #render_lines
	local max_height = math.floor(vim.o.lines / 3)
	local win_height = math.min(total_lines, max_height)

	local win_id, buf_id = win_util.create_bottom_overlay({
		content = render_lines,
		title = args.title or "Keymaps",
		height = win_height,
	})

	menu_win = win_id
	menu_buf = buf_id

	-- Syntax highlighting
	vim.api.nvim_buf_call(buf_id, function()
		-- Highlight all [something] patterns anywhere on the line
		vim.cmd([=[syntax match SpecialKey /\[[^\]]*\]/]=])
		vim.cmd("highlight link SpecialKey Comment")

		-- Highlight keys
		vim.cmd([=[syntax match KeyName /\(\[[^]]\+\] \+\)\@<=\S\+/]=])
		vim.cmd("highlight link KeyName Boolean")

		vim.cmd([=[syntax match HeaderName /^%#HeaderName#.*/ contains=IGNORE]=])
		vim.cmd([=[syntax match Title /^\S.*/]=])
	end)

	-- Clean up header markers
	local clean_lines = {}
	for _, l in ipairs(render_lines) do
		table.insert(clean_lines, (l:gsub("%%#HeaderName#", "")))
	end
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, clean_lines)

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf_id, "cursorline", false)

	-- 6. Keymaps and Interaction
	-- Close maps
	local opts = { nowait = true, noremap = true, silent = true, buffer = buf_id }
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)

	-- Explicit scroll maps (though native <C-d>/<C-u> works in normal mode)
	-- We add them just to be safe and explicit as requested
	vim.keymap.set("n", "<C-d>", "<C-d>", { buffer = buf_id, noremap = true })
	vim.keymap.set("n", "<C-u>", "<C-u>", { buffer = buf_id, noremap = true })

	vim.cmd("redraw")

	require("oz.util").inactive_echo("Scroll: <C-d>/<C-u> | Close: q/<Esc>")
end

-- Show interactive menu
---@param title string
---@param items {key: string, desc: string, cb: function}[]|{title: string, items: {key: string, desc: string, cb: function}[]}[]
function M.show_menu(title, items)
	close_menu() -- Close any existing menu

	-- Store current window to restore focus
	local start_win = vim.api.nvim_get_current_win()

	local key_map = {}
	local lines = {}
	local max_width = 0

	-- Helper to process a list of items
	local function process_item_list(list)
		for _, item in ipairs(list) do
			local key_display = item.key:gsub(" ", "<Space>")
			local desc = item.desc
			local entry = string.format(" %-3s %s", key_display, desc)
			table.insert(lines, { text = entry, key = item.key, cb = item.cb })
			key_map[item.key] = item.cb
			if #entry > max_width then
				max_width = #entry
			end
		end
	end

	-- Check if items are grouped or flat
	local is_grouped = false
	if items[1] and items[1].items then
		is_grouped = true
	end

	local render_lines = {}

	if is_grouped then
		local col_width = 40 -- Minimum column width
		local win_width = vim.o.columns
		local num_cols = math.floor(win_width / col_width)
		if num_cols < 1 then
			num_cols = 1
		end

		for _, group in ipairs(items) do
			table.insert(render_lines, string.format("%%#HeaderName#%s", group.title))
			for _, item in ipairs(group.items) do
				local key_display = item.key:gsub(" ", "<Space>")
				table.insert(render_lines, string.format(" %-3s %s", key_display, item.desc))
				key_map[item.key] = item.cb
			end
			table.insert(render_lines, "") -- spacer
		end
	else
		-- Flat list: render in columns
		process_item_list(items)
		local col_width = max_width + 4
		local win_width = vim.o.columns
		local num_cols = math.floor(win_width / col_width)
		if num_cols < 1 then
			num_cols = 1
		end

		local num_rows = math.ceil(#lines / num_cols)

		for r = 1, num_rows do
			local line_parts = {}
			for c = 1, num_cols do
				local idx = (c - 1) * num_rows + r
				if idx <= #lines then
					local entry = lines[idx]
					local padding = string.rep(" ", col_width - #entry.text)
					table.insert(line_parts, entry.text .. padding)
				end
			end
			table.insert(render_lines, table.concat(line_parts))
		end
	end

	-- Create Window
	local win_id, buf_id = win_util.create_bottom_overlay({
		content = render_lines,
		title = title,
	})

	menu_win = win_id
	menu_buf = buf_id

	-- Syntax highlighting
	vim.api.nvim_buf_call(buf_id, function()
		vim.cmd([[syntax match SpecialKey /^ \S\+/]])
		vim.cmd("highlight link SpecialKey @attribute")
		vim.cmd([[syntax match HeaderName /^%#HeaderName#.*/ contains=IGNORE]]) -- Hide the marker
		if is_grouped then
			vim.cmd([[syntax match Title /^\S.*/]])
		end
	end)

	-- Clean up the header markers if used
	if is_grouped then
		local clean_lines = {}
		for _, l in ipairs(render_lines) do
			table.insert(clean_lines, (l:gsub("%%#HeaderName#", "")))
		end
		vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, clean_lines)
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf_id, "cursorline", false)

	-- Restore focus to the original window
	if vim.api.nvim_win_is_valid(start_win) then
		vim.api.nvim_set_current_win(start_win)
	end

	vim.cmd("redraw")

	-- Blocking wait for input
	local ok, char_code = pcall(vim.fn.getchar)
	if ok and type(char_code) == "number" then
		local char = vim.fn.nr2char(char_code)
		if key_map[char] then
			close_menu()
			key_map[char]()
		elseif char == "q" or char == "\27" then -- q or Esc
			close_menu()
		else
			-- Unknown key, just close? Or stay open?
			-- Usually strictly transient menus close on invalid input or execute it in original buffer
			-- For safety and "Magit-like" feel, let's close.
			close_menu()
		end
	else
		close_menu()
	end
end

-- Export public close function
function M.close()
	close_window()
	close_menu()
end

return M
