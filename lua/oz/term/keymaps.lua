local M = {}
local util = require("oz.term.util")

local function open_entry(file)
	if not util.is_readable(file, {}) then
		return false
	end
	vim.cmd.wincmd("t")
	vim.cmd("edit " .. vim.fn.fnameescape(file))
	return true
end

local function try_jump_file(buf, line)
	local oz_cwd = util.get_oz_cwd(buf)
	local old_cwd = vim.fn.getcwd()

	local changed = pcall(vim.api.nvim_set_current_dir, oz_cwd)
	local qf = vim.fn.getqflist({ lines = { line }, efm = table.concat(util.EFM_PATTERNS, ",") })
	if changed then
		pcall(vim.api.nvim_set_current_dir, old_cwd)
	end

	local entry = qf.items and qf.items[1]
	if not entry or entry.valid ~= 1 then
		return false
	end

	local filename = entry.filename
	if (not filename or filename == "") and entry.bufnr > 0 then
		filename = vim.api.nvim_buf_get_name(entry.bufnr)
	end

	if not filename or filename == "" then
		return false
	end

	if not (filename:match("^/") or filename:match("^%a:")) then
		filename = oz_cwd .. "/" .. filename
	end

	if not open_entry(filename) then
		return false
	end

	local lnum = entry.lnum > 0 and entry.lnum or 1
	local col = entry.col > 0 and entry.col or 1
	vim.api.nvim_win_set_cursor(0, { lnum, col - 1 })
	return true
end

local function try_open_url(line)
	local url = vim.fn.matchstr(line, util.URL_PATTERN)
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

local function try_cword()
	local file = vim.fn.expand("<cfile>")
	if not file or not open_entry(file) then
		return false
	end
	return true
end

local function grab_to_qf(buf)
	local oz_cwd = util.get_oz_cwd(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	local old_cwd = vim.fn.getcwd()
	local changed = pcall(vim.api.nvim_set_current_dir, oz_cwd)
	local qf = vim.fn.getqflist({ lines = lines, efm = table.concat(util.EFM_PATTERNS, ",") })
	if changed then
		pcall(vim.api.nvim_set_current_dir, old_cwd)
	end

	local items = {}
	local readable_cache = {}
	for _, item in ipairs(qf.items or {}) do
		if item.valid == 1 then
			local filename = item.filename
			if (not filename or filename == "") and item.bufnr > 0 then
				filename = vim.api.nvim_buf_get_name(item.bufnr)
			end

			if filename and filename ~= "" then
				local full_path = filename
				if not (full_path:match("^/") or full_path:match("^%a:")) then
					full_path = oz_cwd .. "/" .. full_path
				end

				if util.is_readable(full_path, readable_cache) then
					item.filename = full_path
					table.insert(items, item)
				end
			end
		end
	end

	if #items > 0 then
		vim.fn.setqflist(items, "r")
		vim.cmd("copen")
	else
		vim.notify("No valid locations found in terminal output.", vim.log.levels.INFO)
	end
end

function M.setup(buf)
	vim.keymap.set("n", "<CR>", function()
		local line = vim.api.nvim_get_current_line()
		if try_jump_file(buf, line) or try_cword() or try_open_url(line) then
			return
		end
		vim.notify("No entry found under cursor.", vim.log.levels.INFO)
	end, { buffer = buf, silent = true, desc = "Jump to location or open URL" })

	vim.keymap.set("n", "<C-q>", function()
		grab_to_qf(buf)
	end, { buffer = buf, silent = true, desc = "Grab all locations to quickfix" })

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

	vim.keymap.set("n", "r", function()
		local cmd = vim.b[buf].oz_cmd
		if cmd then
			require("oz.term.executor").run(cmd)
		end
	end, { buffer = buf, silent = true, desc = "Rerun command" })

	-- Help
	vim.keymap.set("n", "g?", function()
		require("oz.util.help_keymaps").show_maps({})
	end, { buffer = buf, desc = "Show all available keymaps" })
end

return M
