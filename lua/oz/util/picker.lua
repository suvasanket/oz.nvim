local api = vim.api
local fn = vim.fn

local M = {}

-- Performance: Local aliases for fast access
local nvim_buf_set_lines = api.nvim_buf_set_lines
local nvim_buf_add_highlight = api.nvim_buf_add_highlight
local nvim_buf_clear_namespace = api.nvim_buf_clear_namespace
local nvim_win_is_valid = api.nvim_win_is_valid
local nvim_set_option_value = api.nvim_set_option_value

local state = {
	ns = api.nvim_create_namespace("ivy_picker"),
	prompt_ns = api.nvim_create_namespace("ivy_picker_prompt"),
	items = {},
	filtered = {},
	keys = {},
	key_to_items = {},
	selected = 0,
	query = "",
	closing = false,
}

local function setup_highlights()
	require("oz.util.hl").setup_hls({
		"ozHelpEcho",
		-- { OzPickerNorm = "Comment" },
		-- { Title = { bold = true, link = "Normal" } },
	})
end

local function normalize_items(items)
	local normalized, keys, key_to_items = {}, {}, {}
	for i, item in ipairs(items) do
		local n_item = type(item) == "table"
				and { key = tostring(item.key or item[1] or ""), value = item.value ~= nil and item.value or item[2] }
			or { key = tostring(item), value = item }

		normalized[i] = n_item
		keys[i] = n_item.key
		if not key_to_items[n_item.key] then
			key_to_items[n_item.key] = { n_item }
		else
			table.insert(key_to_items[n_item.key], n_item)
		end
	end
	return normalized, keys, key_to_items
end

local function close_picker()
	if state.closing then
		return
	end
	state.closing = true

	if state.aug then
		pcall(api.nvim_del_augroup_by_id, state.aug)
	end
	if api.nvim_get_mode().mode == "i" then
		vim.cmd("stopinsert")
	end

	if state.old_cmdheight then
		vim.o.cmdheight = state.old_cmdheight
	end
	if state.old_laststatus then
		vim.o.laststatus = state.old_laststatus
	end

	if state.original_win and nvim_win_is_valid(state.original_win) then
		pcall(api.nvim_set_current_win, state.original_win)
	end

	local wins = { state.prompt_win, state.result_win }
	local bufs = { state.prompt_buf, state.result_buf }
	for _, win in ipairs(wins) do
		if win and nvim_win_is_valid(win) then
			pcall(api.nvim_win_close, win, true)
		end
	end
	for _, buf in ipairs(bufs) do
		if buf and api.nvim_buf_is_valid(buf) then
			pcall(api.nvim_buf_delete, buf, { force = true })
		end
	end

	-- Reset state but keep namespaces
	local ns, pns = state.ns, state.prompt_ns
	state = {
		ns = ns,
		prompt_ns = pns,
		items = {},
		filtered = {},
		keys = {},
		key_to_items = {},
		selected = 0,
		query = "",
		closing = false,
	}
end

local function render_results()
	local buf = state.result_buf
	if not buf or state.closing then
		return
	end

	local filtered = state.filtered
	local count = #filtered
	if count == 0 then
		state.selected = 0
	else
		state.selected = math.max(0, math.min(state.selected, count - 1))
	end

	local height = state.height or 10
	local start_idx = math.max(1, state.selected - math.floor(height / 2) + 1)
	local end_idx = math.min(count, start_idx + height - 1)
	if end_idx - start_idx + 1 < height then
		start_idx = math.max(1, end_idx - height + 1)
	end

	local res_lines = {}
	local pointer, no_pointer = " ▸ ", "   "
	if count == 0 then
		res_lines = { no_pointer .. "(no matches)" }
	else
		for i = start_idx, end_idx do
			table.insert(res_lines, ((i - 1 == state.selected) and pointer or no_pointer) .. filtered[i].key)
		end
	end

	nvim_set_option_value("modifiable", true, { buf = buf })
	nvim_buf_set_lines(buf, 0, -1, false, res_lines)
	nvim_set_option_value("modifiable", false, { buf = buf })

	local ns = state.ns
	nvim_buf_clear_namespace(buf, ns, 0, -1)
	if count > 0 then
		for i = 1, #res_lines do
			if (start_idx + i - 2) == state.selected then
				nvim_buf_add_highlight(buf, ns, "Title", i - 1, 0, #pointer)
				nvim_buf_add_highlight(buf, ns, "Title", i - 1, #pointer, -1)
			else
                nvim_buf_add_highlight(buf, ns, "ozHelpEcho", i - 1, 0, -1)
			end
		end
	end
end

local function on_type()
	if state.closing or not state.prompt_buf then
		return
	end
	local line = api.nvim_buf_get_lines(state.prompt_buf, 0, 1, false)[1] or ""
	local t = state.title_opts
	local prefix = (t.title or "") .. (t.separator or " > ")

	if not vim.startswith(line, prefix) then
		nvim_buf_set_lines(state.prompt_buf, 0, 1, false, { prefix .. state.query })
		api.nvim_win_set_cursor(state.prompt_win, { 1, #prefix + #state.query })
		return
	end

	local query = line:sub(#prefix + 1)
	if query ~= state.query then
		state.query = query
		state.selected = 0

		if query == "" then
			state.filtered = state.items
		else
			local ok, matched = pcall(fn.matchfuzzy, state.keys, query)
			if not ok then
				state.filtered = {}
			else
				local res, used = {}, {}
				for _, k in ipairs(matched) do
					for _, item in ipairs(state.key_to_items[k]) do
						local id = item.key .. "\0" .. tostring(item.value)
						if not used[id] then
							used[id] = true
							table.insert(res, item)
						end
					end
				end
				state.filtered = res
			end
		end
		render_results()

		-- Inline render decorations for speed
		local pbuf, pns = state.prompt_buf, state.prompt_ns
		nvim_buf_clear_namespace(pbuf, pns, 0, -1)
		if #t.title > 0 then
			nvim_buf_add_highlight(pbuf, pns, t.highlight or "Special", 0, 0, #t.title)
		end
		if #t.separator > 0 then
			nvim_buf_add_highlight(pbuf, pns, t.separator_highlight or "Comment", 0, #t.title, #t.title + #t.separator)
		end
		api.nvim_buf_set_extmark(pbuf, pns, 0, 0, {
			id = 1,
			virt_text = { { string.format("[%d/%d]", #state.filtered, #state.items), "Comment" } },
			virt_text_pos = "right_align",
		})
	end
end

--- @alias oz.util.picker.item string | {key: string, value: any} | [string, any]

--- @class oz.util.picker.title_opts
--- @field title string The title text.
--- @field separator? string Separator between title and query (default: " > ").
--- @field highlight? string Highlight group for the title (default: "Special").
--- @field separator_highlight? string Highlight group for the separator (default: "Comment").

--- @class oz.util.picker.opts
--- @field on_select function(item: any|nil) Callback when an item is selected (returns item.value) or nil on cancellation.
--- @field height? number Height of the results window (default: 10).
--- @field title? string|oz.util.picker.title_opts Title string or configuration table.

--- Open a fuzzy picker in "Ivy" style at the bottom of the editor.
--- @param items oz.util.picker.item[] List of items to pick from.
--- @param opts oz.util.picker.opts Configuration options.
function M.pick(items, opts)
	opts = opts or {}
	local on_select = opts.on_select
	assert(on_select, "on_select required")
	setup_highlights()
	if state.prompt_buf then
		close_picker()
	end

	state.items, state.keys, state.key_to_items = normalize_items(items)
	state.filtered, state.selected, state.query, state.callback = state.items, 0, "", on_select
	state.old_cmdheight, state.old_laststatus = vim.o.cmdheight, vim.o.laststatus
	state.height = opts.height or 10
	state.title_opts = type(opts.title) == "table" and opts.title
		or { title = tostring(opts.title or ""), separator = " > " }
	state.title_opts.separator = state.title_opts.separator or " > "

	state.prompt_buf = api.nvim_create_buf(false, true)
	state.result_buf = api.nvim_create_buf(false, true)
	for _, b in ipairs({ state.prompt_buf, state.result_buf }) do
		nvim_set_option_value("buftype", "nofile", { buf = b })
		nvim_set_option_value("bufhidden", "wipe", { buf = b })
	end
	nvim_set_option_value("modifiable", false, { buf = state.result_buf })

	vim.o.laststatus, vim.o.cmdheight = 2, 0
	vim.cmd("botright " .. state.height .. "split")
	state.result_win = api.nvim_get_current_win()
	api.nvim_win_set_buf(state.result_win, state.result_buf)
	vim.cmd("aboveleft 1split")
	state.prompt_win = api.nvim_get_current_win()
	api.nvim_win_set_buf(state.prompt_win, state.prompt_buf)

	local w_opts = {
		number = false,
		relativenumber = false,
		signcolumn = "no",
		winfixheight = true,
		winhl = "Normal:Normal,EndOfBuffer:Normal,StatusLine:Normal,StatusLineNC:Normal",
		fillchars = "eob: ,stl: ,stlnc: ,horiz: ",
		statusline = " ",
		ruler = false,
	}
	for _, w in ipairs({ state.prompt_win, state.result_win }) do
		for k, v in pairs(w_opts) do
			pcall(api.nvim_set_option_value, k, v, { win = w })
		end
	end

	state.original_win = fn.win_getid(fn.winnr("#"))
	api.nvim_set_current_win(state.prompt_win)
	local pref = (state.title_opts.title or "") .. state.title_opts.separator
	nvim_buf_set_lines(state.prompt_buf, 0, -1, false, { pref })
	api.nvim_win_set_cursor(state.prompt_win, { 1, #pref })

	render_results()
	local map_opts = { buffer = state.prompt_buf, nowait = true, silent = true }
	vim.keymap.set("i", "<CR>", function()
		local r = (state.filtered[state.selected + 1] or {}).value
		close_picker()
		if on_select then
			on_select(r)
		end
	end, map_opts)
	vim.keymap.set("i", "<Esc>", function()
		close_picker()
		if on_select then
			on_select(nil)
		end
	end, map_opts)
	vim.keymap.set("i", "<C-c>", function()
		close_picker()
		if on_select then
			on_select(nil)
		end
	end, map_opts)

	local function map_nav(k, d)
		vim.keymap.set("i", k, function()
			if #state.filtered > 0 then
				state.selected = (state.selected + d) % #state.filtered
				render_results()
			end
		end, map_opts)
	end
	map_nav("<Down>", 1)
	map_nav("<Up>", -1)
	map_nav("<Tab>", 1)
	map_nav("<S-Tab>", -1)

	state.aug = api.nvim_create_augroup("IvyPicker", { clear = true })
	api.nvim_create_autocmd("TextChangedI", { group = state.aug, buffer = state.prompt_buf, callback = on_type })
	api.nvim_create_autocmd("BufWipeout", {
		group = state.aug,
		buffer = state.prompt_buf,
		once = true,
		callback = function()
			if not state.closing then
				close_picker()
				if on_select then
					on_select(nil)
				end
			end
		end,
	})
	vim.cmd("startinsert!")
end

return M
