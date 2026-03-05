local M = {}
local util = require("oz.util")
local term_util = require("oz.term.util")

local function open_entry(file, oz_cwd, lnum, col)
	if not (file:match("^/") or file:match("^%a:")) then
		file = oz_cwd .. "/" .. file
	end
	if not term_util.is_readable(file, {}) then
		return false
	end
	vim.cmd.wincmd("t")
	vim.cmd("edit " .. vim.fn.fnameescape(file))

	if lnum or col then
		local target_lnum = lnum and lnum > 0 and lnum or 1
		local target_col = col and col > 0 and col or 1
		vim.api.nvim_win_set_cursor(0, { target_lnum, target_col - 1 })
	end

	return true
end

local function try_jump_file(buf)
	local entries = require("oz.term.executor").get_entries(buf)
	if not entries then
		return false
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local lnum = cursor[1]
	local col = cursor[2]

	local line_entries = entries[lnum]
	if not line_entries then
		return false
	end

	local best_entry = nil
	for _, entry in ipairs(line_entries) do
		if not best_entry then
			best_entry = entry
		end
		if col >= entry.start and col < entry["end"] then
			best_entry = entry
			break
		end
	end

	if best_entry and best_entry.filename then
		local oz_cwd = term_util.get_oz_cwd(buf)
		return open_entry(best_entry.filename, oz_cwd, best_entry.lnum, best_entry.col)
	end

	return false
end

local function try_open_url(line)
	local url = vim.fn.matchstr(line, term_util.URL_PATTERN)
	if url == "" then
		return false
	end

	if vim.ui.open then
		vim.ui.open(url)
	else
		vim.fn.jobstart({ "open", url }, { detach = true })
	end
	return true
end

local function try_cword(buf)
	local oz_cwd = term_util.get_oz_cwd(buf)
	local file = vim.fn.expand("<cfile>")
	if not file then
		return false
	end

	local valid_path = term_util.find_valid_path(file, oz_cwd)
	if not valid_path or not open_entry(valid_path, oz_cwd) then
		return false
	end
	return true
end

local function grab_to_qf(buf)
	local entries = require("oz.term.executor").get_entries(buf)
	if not entries then
		util.Notify("No parsed entries found.", "info", "oz_term")
		return
	end

	local items = {}

	-- Sort line numbers to keep quickfix list in order
	local lnums = {}
	for k in pairs(entries) do
		table.insert(lnums, k)
	end
	table.sort(lnums)

	for _, lnum in ipairs(lnums) do
		for _, entry in ipairs(entries[lnum]) do
			if entry.entry and entry.entry.valid == 1 then
				local item = vim.deepcopy(entry.entry)
				item.bufnr = vim.fn.bufnr(entry.filename)
				table.insert(items, item)
			end
		end
	end

	if #items > 0 then
		vim.fn.setqflist(items, "r")
		vim.cmd("copen")
	else
		util.Notify("No valid errors found in stdout.", "info", "oz_term")
	end
end

function M.setup(buf)
	vim.keymap.set("n", "<CR>", function()
		local line = vim.api.nvim_get_current_line()
		if try_jump_file(buf) or try_cword(buf) or try_open_url(line) then
			return
		end
		util.Notify("No entry found under cursor.", "info", "oz_term")
	end, { buffer = buf, silent = true, desc = "Visit location under cursor" })

	vim.keymap.set("n", "<C-q>", function()
		grab_to_qf(buf)
	end, { buffer = buf, silent = true, desc = "Grab all errors to quickfix" })

	vim.keymap.set("n", "q", function()
		local manager = require("oz.term.manager")
		local id = vim.b[buf].oz_term_id
		local inst = manager.instances[id]

		if inst and inst.job_active then
			local ok, res = pcall(vim.fn.confirm, "Job is still running. Close anyway?", "&Yes\n&No", 1)
			if ok and res == 1 then
				manager.close(id)
			end
		else
			manager.close(id)
		end
	end, { buffer = buf, silent = true, desc = "Close terminal" })

	vim.keymap.set("n", "<C-r>", function()
		local cmd = vim.b[buf].oz_cmd
		if cmd then
			require("oz.term.executor").run(cmd, { cwd = vim.b[buf].oz_cwd })
		end
	end, { buffer = buf, silent = true, desc = "Rerun command" })

	vim.keymap.set("n", "e", function()
		local cmd = vim.b[buf].oz_cmd
		if cmd then
			local input = util.inactive_input(":Term ", cmd, "shellcmd")
			if input then
				require("oz.term.executor").run(input, { cwd = vim.b[buf].oz_cwd })
			end
		end
	end, { buffer = buf, silent = true, desc = "Edit command" })

	vim.keymap.set("n", "r", function()
		local root = util.GetProjectRoot()
		if not root then
			util.Notify("No root found!, running in cwd", "error", "oz_term")
			root = vim.fn.getcwd()
		end
		require("oz.term.executor").run(vim.b[buf].oz_cmd, { cwd = root })
	end, { buffer = buf, silent = true, desc = "Run cmd in root of the project" })

	-- Help
	vim.keymap.set("n", "g?", function()
		util.show_maps({})
	end, { buffer = buf, desc = "Show all available keymaps" })
end

return M
