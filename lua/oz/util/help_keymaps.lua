--- @class oz.util.help_keymaps
local M = {}
local util = require("oz.util")

-- Module-level tracking for singleton behavior
local key_help_win = nil
local key_help_buf = nil
local menu_win = nil
local menu_buf = nil
local menu_prev_win = nil
local original_guicursor = nil

--- Internal helper: Close existing window and buffer.
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

--- Internal helper: Close the interactive menu.
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

--- helper: filter keys from user provided 'key'
---@param tbl table
---@param str string
---@return table
---@return string[]
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

--- Display a window showing available keymaps.
---@param args {title?: string, key?: string, group?: table<string, string[]>, show_general?: boolean, on_open?: function}
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
	if args.show_general == nil or args.show_general == true then
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
	local render_lines = { "" } -- Initial padding line
	for _, group in ipairs(groups) do
		if group.title then
			table.insert(render_lines, string.format(" %%#HeaderName#%s", group.title))
		end

		local items = group.items
		local num_rows = math.ceil(#items / num_cols)

		for r = 1, num_rows do
			local line_parts = { " " } -- Left padding
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

	-- Remove trailing empty line and add final padding line
	if render_lines[#render_lines] == "" then
		render_lines[#render_lines] = "" -- Ensure it stays for padding
	else
		table.insert(render_lines, "")
	end

	-- 5. Create Window with Height Constraint
	local total_lines = #render_lines
	local max_height = math.floor(vim.o.lines / 3)
	local win_height = math.min(total_lines, max_height)

	local win_id, buf_id = util.create_bottom_overlay({
		content = render_lines,
		title = args.title or "Available Keymaps",
		height = win_height,
	})

	menu_win = win_id
	menu_buf = buf_id

	-- Syntax highlighting
	vim.api.nvim_buf_call(buf_id, function()
        util.setup_hls({ "OzActive" })
		-- Highlight all [something] patterns anywhere on the line
		vim.cmd([=[syntax match OzCmdPrompt /\[[^\]]*\]/]=])

		-- Highlight keys
		vim.cmd([=[syntax match OzActive /\(\[[^]]\+\] \+\)\@<=\S\+/]=])
	end)

	-- Clean up header markers and apply line highlights
	local clean_lines = {}
	local ns = vim.api.nvim_create_namespace("oz_help_maps")
	for i, l in ipairs(render_lines) do
		local is_header = l:find("%%#HeaderName#") ~= nil
		local line_text = l:gsub("%%#HeaderName#", "")
		table.insert(clean_lines, line_text)
		if is_header then
			vim.api.nvim_buf_add_highlight(buf_id, ns, "Title", i - 1, 0, -1)
		end
	end
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, clean_lines)

	vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_id })
	vim.api.nvim_set_option_value("cursorline", false, { win = win_id })

	-- 6. Keymaps and Interaction
	-- Close maps
	local opts = { nowait = true, noremap = true, silent = true, buffer = buf_id }
	util.Map("n", { "q", "<C-c>", "<esc>" }, function()
		M.close()
		vim.api.nvim_echo({ { "" } }, false, {})
	end, opts)

	if args.on_open then
		args.on_open()
	end

	vim.cmd("redraw")
end

--- Show an interactive menu for switches and actions.
---@param title string The menu title.
---@param items {key: string, desc: string, cb: function, type?: "switch"|"action", name?: string, default?: boolean}[]|{title: string, items: {key: string, desc: string, cb: function, type?: "switch"|"action", name?: string, default?: boolean}[]}[]
function M.show_menu(title, items)
	close_menu() -- Close any existing menu

	-- Store current window to restore focus
	local start_win = vim.api.nvim_get_current_win()

	-- Normalize items to groups if flat
	local groups = items
	if not (items[1] and items[1].items) then
		groups = { { items = items } }
	end

	local active_switches = {}
	local switch_map = {}
	local action_map = {}

	-- Initialize state
	for _, group in ipairs(groups) do
		for _, item in ipairs(group.items) do
			if item.type == "switch" then
				switch_map[item.key] = item
				if item.default then
					active_switches[item.key] = true
				end
			else
				action_map[item.key] = item
			end
		end
	end

	local win_id, buf_id = nil, nil

	local function get_active_flags()
		local flags = {}
		-- Iterate in defined order for consistency? or just map keys?
		-- Map keys might be random order. Let's iterate groups to preserve order if possible,
		-- or just active_switches keys.
		for _, group in ipairs(groups) do
			for _, item in ipairs(group.items) do
				if item.type == "switch" and active_switches[item.key] then
					table.insert(flags, item.name)
				end
			end
		end
		return flags
	end

	local function render()
		local render_lines = { "" } -- Top padding
		local highlight_queue = {} -- {group, line, col_start, col_end}
		local line_idx = 1 -- Start after top padding

		-- Helper to layout
		local max_width = 0
		local processed_groups = {}

		for _, group in ipairs(groups) do
			local p_group = { title = group.title, items = {} }
			for _, item in ipairs(group.items) do
				local key_display = item.key:gsub(" ", "<Space>")
				local text
				if item.type == "switch" then
					-- Format: -s --signoff
					text = string.format(" %-3s %-12s %s", key_display, item.name, item.desc)
				else
					text = string.format(" %-3s %s", key_display, item.desc)
				end

				table.insert(p_group.items, {
					text = text,
					key = item.key,
					item = item,
					key_display = key_display,
				})
				if #text > max_width then
					max_width = #text
				end
			end
			table.insert(processed_groups, p_group)
		end

		local col_width = max_width + 4
		local win_width = vim.o.columns
		local num_cols = math.floor(win_width / col_width)
		if num_cols < 1 then
			num_cols = 1
		end

		for _, group in ipairs(processed_groups) do
			if group.title then
				table.insert(render_lines, " " .. group.title) -- Horizontal padding
				table.insert(highlight_queue, { "Title", line_idx, 1, -1 })
				line_idx = line_idx + 1
			end

			local items_list = group.items
			local num_rows = math.ceil(#items_list / num_cols)

			for r = 1, num_rows do
				local line_parts = { " " } -- Left padding
				local current_len = 1
				for c = 1, num_cols do
					local idx = (c - 1) * num_rows + r
					if idx <= #items_list then
						local entry = items_list[idx]
						local padding = string.rep(" ", col_width - #entry.text)
						local part = entry.text .. padding
						table.insert(line_parts, part)

						-- Determine Highlight Groups
						local active = active_switches[entry.key]
                        util.setup_hls({ "OzActive" })
						local key_hl = "OzActive"
						local flag_hl = "OzCmdPrompt"

						if active then
							key_hl = "Boolean"
							flag_hl = "Boolean"
						end

						-- Find positions
						local s_key = part:find(vim.pesc(entry.key_display))
						if s_key then
							local e_key = s_key + #entry.key_display
							table.insert(
								highlight_queue,
								{ key_hl, line_idx, current_len + s_key - 1, current_len + e_key - 1 }
							)
						end

						if entry.item.type == "switch" then
							local s_name = part:find(vim.pesc(entry.item.name), (s_key or 0) + #entry.key_display)
							if s_name then
								local e_name = s_name + #entry.item.name
								table.insert(
									highlight_queue,
									{ flag_hl, line_idx, current_len + s_name - 1, current_len + e_name - 1 }
								)
							end
						end

						current_len = current_len + #part
					end
				end
				table.insert(render_lines, table.concat(line_parts))
				line_idx = line_idx + 1
			end
			table.insert(render_lines, "") -- spacer
			line_idx = line_idx + 1
		end
		table.insert(render_lines, "") -- Bottom padding

		-- Window Creation / Update
		if not win_id or not vim.api.nvim_win_is_valid(win_id) then
			win_id, buf_id = util.create_bottom_overlay({
				content = render_lines,
				title = title,
			})
			menu_win = win_id
			menu_buf = buf_id
		else
			vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, render_lines)
			vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
		end

		-- Apply Highlights
		vim.api.nvim_buf_clear_namespace(buf_id, -1, 0, -1)
		local ns = vim.api.nvim_create_namespace("oz_menu_switches")
		for _, hl in ipairs(highlight_queue) do
			vim.api.nvim_buf_add_highlight(buf_id, ns, hl[1], hl[2], hl[3], hl[4])
		end
	end

	-- Interaction Loop
	while true do
		render()
		vim.cmd("redraw")

		local ok, char_code = pcall(vim.fn.getchar)
		if not ok then
			close_menu()
			break
		end

		local char
		if type(char_code) == "number" then
			char = vim.fn.nr2char(char_code)
		else
			char = char_code
		end

		if char == "-" then
			-- Switch Mode
			local next_ok, next_code = pcall(vim.fn.getchar)
			if next_ok then
				local next_char
				if type(next_code) == "number" then
					next_char = vim.fn.nr2char(next_code)
				else
					next_char = next_code
				end
				local switch_key = "-" .. next_char
				if switch_map[switch_key] then
					active_switches[switch_key] = not active_switches[switch_key]
				end
			end
		elseif action_map[char] then
			-- Action Mode
			close_menu()
			if vim.api.nvim_win_is_valid(start_win) then
				vim.api.nvim_set_current_win(start_win)
			end
			action_map[char].cb(get_active_flags())
			break
		elseif char == "q" or char == "\27" then
			close_menu()
			if vim.api.nvim_win_is_valid(start_win) then
				vim.api.nvim_set_current_win(start_win)
			end
			break
		end
		-- Unknown keys are ignored in the loop
	end
end

--- Close all help/menu windows.
function M.close()
	close_window()
	close_menu()
end

return M
