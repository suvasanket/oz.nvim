local M = {}

-- Module-level tracking for singleton behavior
local key_help_win = nil
local key_help_buf = nil

--- Internal helper: Close existing window and buffer
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

--- helper: filter keys from user provided 'key'
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

--- get header str fmt
---@param str string
local function header_fmt(str)
	return string.format("█%s█", str)
end

--- Helper to sort keys, format lines, and append to buffer content
local function append_keys_to_content(content_tbl, map_data_tbl, keys_to_process)
	local keys = keys_to_process or vim.tbl_keys(map_data_tbl)
	table.sort(keys)

	for _, key in ipairs(keys) do
		local data = map_data_tbl[key]
		if data then
			table.sort(data.modes)
			local modes_l = "[" .. table.concat(data.modes, ", ") .. "]"
			local line = string.format(" %s  %s 󱦰 %s", modes_l, '"' .. key .. '"', data.desc)
			table.insert(content_tbl, line)
		end
	end
end

--- show mappings
---@param args {title: string, no_empty: boolean, key: string, group: table<string, string[]>, subtext: string[], parent_buf: integer|nil, float: boolean, on_open: function|nil}
---@return integer|nil
---@return integer|nil
function M.show_maps(args)
	-- 1. Enforce Singleton: Close any existing instances
	close_window()

	local start_win = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()
	local modes = { "n", "v", "i", "t" }
	local sub_keys = {}
	local all_keymaps = {}

	-- 2. Gather Keymaps Efficiently
	for _, mode in ipairs(modes) do
		local maps = vim.api.nvim_buf_get_keymap(bufnr, mode)
		for _, map in ipairs(maps) do
			local key = map.lhs:gsub(" ", "<Space>")
			local desc = map.desc or map.rhs

			if desc then
				desc = desc:gsub("<Cmd>", ""):gsub("<CR>", "")
			elseif not args.no_empty then
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
		all_keymaps, sub_keys = filter_table(all_keymaps, args.key)
	end

	-- 3. Build Content
	local buf_content = {}
	local has_headers = args and args.group and not vim.tbl_isempty(args.group)

	if has_headers then
		for header_name, keys in pairs(args.group) do
			local group_keys_found = {}
			for _, key in ipairs(keys) do
				if all_keymaps[key] then
					table.insert(group_keys_found, key)
				end
			end

			if #group_keys_found > 0 then
				if #buf_content > 0 then
					table.insert(buf_content, "")
				end
				table.insert(buf_content, header_fmt(header_name))
				append_keys_to_content(buf_content, all_keymaps, group_keys_found)
				for _, key in ipairs(group_keys_found) do
					all_keymaps[key] = nil
				end
			end
		end

		if not vim.tbl_isempty(all_keymaps) then
			table.insert(buf_content, "")
			table.insert(buf_content, header_fmt("unspecified"))
			append_keys_to_content(buf_content, all_keymaps, nil)
		end
	else
		append_keys_to_content(buf_content, all_keymaps, nil)
	end

	if args.subtext then
		table.insert(buf_content, "")
		for _, i in ipairs(args.subtext) do
			table.insert(buf_content, " " .. i)
		end
	end

	if #buf_content == 0 then
		return
	end

	-- 4. Create Buffer
	key_help_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(key_help_buf, 0, -1, false, buf_content)
	vim.bo[key_help_buf].modifiable = false
	vim.bo[key_help_buf].buftype = "nofile"

	vim.api.nvim_buf_call(key_help_buf, function()
		vim.cmd("syntax clear")
		vim.cmd("highlight default BoldKey gui=bold guifg=#99BC85 cterm=bold")
		vim.cmd('syntax match BoldKey /"\\(.*\\)"/ contains=NONE')
		vim.cmd([[
        syntax match Comment /\[.*\]/
        syntax match @keyword /<.*>/
        ]])
		if has_headers then
			vim.cmd("highlight default HeaderName gui=bold guifg=#DFD3C3 guibg=#2F2F2F cterm=bold")
			vim.cmd("highlight default HeaderBlocks guifg=#2F2F2F ctermfg=green")
			vim.cmd("syntax match HeaderName /█.*█/ contains=HeaderBlocks")
			vim.cmd("syntax match HeaderBlocks /[██]/ contained")
		end
	end)

	-- 5. Window Geometry
	local fixed_width = 60
	local max_height = 15
	local max_width = 0

	if args.float then
		for _, line in ipairs(buf_content) do
			local w = vim.fn.strwidth(line)
			if w > max_width then
				max_width = w
			end
		end
	end

	local height = math.min(#buf_content, max_height)
	local width = (max_height > 100) and fixed_width or max_width + 2
	local row = vim.o.lines - height - 4

	local win_opts = {}
	if args.float then
		win_opts = {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = vim.o.columns,
			style = "minimal",
			border = "rounded",
			title = " " .. (args.title or "All keymaps") .. " ",
			title_pos = "left",
			footer = " " .. (args.float and "ctrl-c/esc cancel" or "<C-f> find heading") .. " ",
			footer_pos = "right",
		}
	else
		win_opts = {
			split = "below",
			height = height,
			style = "minimal",
		}
	end

	-- 6. Open Window
	key_help_win = vim.api.nvim_open_win(key_help_buf, true, win_opts)

	if not args.float then
		local wo = vim.wo[key_help_win]
		wo.wrap = false
		wo.foldcolumn = "0"
		wo.signcolumn = "no"
		wo.number = false
		wo.relativenumber = false
	end

	-- 7. Execute on_open callback
	if args.on_open and type(args.on_open) == "function" then
		-- We pass the window and buffer ID to the callback for flexibility
		pcall(args.on_open, key_help_win, key_help_buf)
	end

	-- 8. Keymaps & Cleanup Logic
	local function restore_focus()
		close_window()

		if args.parent_buf and vim.api.nvim_buf_is_valid(args.parent_buf) then
			if
				start_win
				and vim.api.nvim_win_is_valid(start_win)
				and vim.api.nvim_win_get_buf(start_win) == args.parent_buf
			then
				vim.api.nvim_set_current_win(start_win)
			else
				local wins = vim.fn.win_findbuf(args.parent_buf)
				if #wins > 0 then
					vim.api.nvim_set_current_win(wins[1])
				end
			end
		end
	end

	local opts = { buffer = key_help_buf, noremap = true, silent = true }
	vim.keymap.set("n", "q", restore_focus, opts)
	vim.keymap.set("n", "<C-c>", restore_focus, opts)
	vim.keymap.set("n", "<esc>", restore_focus, opts)

	if not args.float then
		vim.keymap.set("n", "<C-f>", function()
			local keys = vim.tbl_keys(args.group or {})
			if #keys == 0 then
				return
			end
			vim.ui.select(keys, {
				prompt = "Jump to section",
				format_item = function(k)
					return k
				end,
			}, function(choice)
				if choice then
					local pattern = header_fmt(choice)
					local pos = vim.fn.searchpos("\\V" .. pattern, "w")
					if pos[1] ~= 0 then
						vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] - 1 })
					end
				end
			end)
		end, opts)
	end

	-- 9. Recursive Key Detection
	if #sub_keys > 0 then
		if vim.api.nvim_win_is_valid(start_win) then
			vim.api.nvim_set_current_win(start_win)
		end

		vim.defer_fn(function()
			local ok, char_code = pcall(vim.fn.getchar)
			if ok and type(char_code) == "number" then
				local char = vim.fn.nr2char(char_code)
				if vim.tbl_contains(sub_keys, char) then
					close_window()
					local full_sequence = args.key .. char
					vim.api.nvim_feedkeys(full_sequence, "m", false)
				else
					close_window()
				end
			else
				close_window()
			end
		end, 10)
	end

	return key_help_win, key_help_buf
end

-- Export public close function
function M.close()
	close_window()
end

return M
