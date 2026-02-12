local M = {}
local manager = require("oz.term.manager")

local function highlight(buf)
	local util = require("oz.term.util")
	vim.api.nvim_buf_call(buf, function()
		vim.cmd([[
            syntax clear
            syntax match Label /^\(Exit code\|Time\):/
            syntax match Comment /^----------------------------------------$/
            syntax match Comment /^Exit code: 0/
            syntax match DiagnosticError /^Exit code: [^0]\d*/
            syntax match Comment /^Time:.*/
        ]])
	end)

	vim.schedule(function()
		local win = vim.fn.bufwinid(buf)
		if win ~= -1 then
			vim.api.nvim_win_call(win, function()
				-- Highlight URLs
				vim.fn.matchadd("@attribute", util.URL_PATTERN)
			end)
		end

		-- Performance guards
		local line_count = vim.api.nvim_buf_line_count(buf)
		if line_count > 5000 then
			return
		end

		-- More efficient total byte count check
		local total_bytes = vim.api.nvim_buf_get_offset(buf, line_count)
		if total_bytes > 200000 then
			return
		end

		-- Highlight potential file locations using EFM and verifying existence
		local oz_cwd = util.get_oz_cwd(buf)
		local ns = vim.api.nvim_create_namespace("oz_term_files")
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

		local efm = table.concat(util.EFM_PATTERNS, ",") .. ",%f" -- all the efm and only file
		local old_cwd = vim.fn.getcwd()
		local changed_dir = pcall(vim.api.nvim_set_current_dir, oz_cwd)

		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local readable_cache = {}

		for i, line in ipairs(lines) do
			if line ~= "" and #line < 1000 then
				local start_idx = 0
				while true do
					local match = vim.fn.matchstrpos(line, util.PATH_PATTERN, start_idx)
					local text = match[1]
					local start_pos = match[2]
					local end_pos = match[3]
					if text == "" then
						break
					end

					-- Check if this specific chunk is a valid location according to EFM
					local sub_qf = vim.fn.getqflist({ lines = { text }, efm = efm })
					local sub_entry = sub_qf.items and sub_qf.items[1]

					if sub_entry and sub_entry.valid == 1 then
						local filename = sub_entry.filename
						if (not filename or filename == "") and sub_entry.bufnr > 0 then
							filename = vim.api.nvim_buf_get_name(sub_entry.bufnr)
						end

						if filename and filename ~= "" then
							local full_path = filename
							if not (full_path:match("^/") or full_path:match("^%a:")) then
								full_path = oz_cwd .. "/" .. full_path
							end

							if util.is_readable(full_path, readable_cache) then
								vim.api.nvim_buf_add_highlight(buf, ns, "@attribute", i - 1, start_pos, end_pos)
							end
						end
					end
					start_idx = end_pos
				end
			end
		end

		if changed_dir then
			pcall(vim.api.nvim_set_current_dir, old_cwd)
		end
	end)
end

local function ft_init(cmd)
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "oz_term",
		group = vim.api.nvim_create_augroup("oz_term_setup", { clear = true }),
		callback = function(ev)
			local buf = ev.buf
			-- window-local stuff should be deferred
			vim.schedule(function()
				local win = vim.fn.bufwinid(buf)
				if win ~= -1 then
					vim.wo[win].number = false
					vim.wo[win].relativenumber = false
					vim.wo[win].signcolumn = "no"
					vim.wo[win].wrap = false
					vim.wo[win].spell = false
					vim.wo[win].list = false
					vim.wo[win].winbar = string.format("$ %s", cmd)
				end
				highlight(buf)
				require("oz.term.keymaps").setup(buf)
			end)
		end,
	})
	return "oz_term"
end

--- run
---@param cmd string
---@param opts {cwd: string, stdin: string}|nil
function M.run(cmd, opts)
	if not cmd or cmd == "" then
		return
	end
	opts = opts or {}
	local target_id = manager.get_target_id()
	local target_inst = target_id and manager.instances[target_id]
	local reuse_win = nil

	if target_inst and not target_inst.job_active then
		if target_inst.win and vim.api.nvim_win_is_valid(target_inst.win) then
			reuse_win = target_inst.win
		end
	end

	-- Always create a new instance
	local id = manager.next_id()
	local buf_name = "oz_term://" .. id
	local start_cwd = opts.cwd or (vim.uv or vim.loop).cwd()
	local oz_cwd = start_cwd

	-- Handle "cd path && cmd" or "cd path; cmd"
	local cd_path = cmd:match("^%s*cd%s+([^&|;]+)")
	if cd_path then
		cd_path = vim.trim(cd_path)
		-- Resolve relative to start_cwd and get absolute path
		oz_cwd = vim.fn.fnamemodify(start_cwd .. "/" .. cd_path, ":p")
		-- Remove trailing slash if it's a directory but fnamemodify added it
		if oz_cwd:sub(-1) == "/" or oz_cwd:sub(-1) == "\\" then
			oz_cwd = oz_cwd:sub(1, -2)
		end
	end

	local start_time = (vim.uv or vim.loop).hrtime()

	-- create a new window
	require("oz.util.win").create_win("oz_term", {
		win_type = "botright",
		reuse = reuse_win ~= nil,
		content = {},
		callback = function(buf_id, win_id)
			if reuse_win and target_id and target_inst then
				local old_buf = target_inst.buf
				manager.instances[target_id] = nil
				if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
					vim.schedule(function()
						pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
					end)
				end
			end

			vim.api.nvim_win_call(win_id, function()
				if opts.cwd then
					pcall(vim.cmd, "lcd " .. vim.fn.fnameescape(opts.cwd))
				end
				vim.cmd("terminal " .. cmd)

				local buf = vim.api.nvim_get_current_buf()
				local job_id = vim.b[buf].terminal_job_id

				vim.api.nvim_buf_set_name(buf, buf_name)
				vim.b[buf].oz_cmd = cmd
				vim.b[buf].oz_cwd = oz_cwd
				vim.bo[buf].filetype = ft_init(cmd)

				-- Listen for OSC 7 directory changes
				vim.api.nvim_create_autocmd("TermRequest", {
					buffer = buf,
					callback = function(ev)
						local val, n = string.gsub(ev.data.sequence, "\027]7;file://[^/]*", "")
						if n > 0 then
							local dir = val
							if vim.fn.isdirectory(dir) ~= 0 then
								vim.b[ev.buf].oz_cwd = dir
							end
						end
					end,
				})

				manager.register_instance(id, {
					buf = buf,
					win = win_id,
					job_id = job_id,
					job_active = true,
				})

				-- Delete scratch buffer
				if buf ~= buf_id then
					pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
				end
			end)
		end,
	})

	local buf = vim.api.nvim_get_current_buf()
	local job_id = vim.b[buf].terminal_job_id

	-- Update job status when terminal finishes
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = buf,
		once = true,
		callback = function(ev)
			local end_time = (vim.uv or vim.loop).hrtime()
			local duration = (end_time - start_time) / 1e9
			local status = vim.v.event.status
			local terminal_buf = ev.buf
			local final_oz_cwd = vim.b[terminal_buf].oz_cwd

			if manager.instances[id] then
				manager.instances[id].job_active = false
			end

			-- Capture lines before deleting buffer
			local lines = vim.api.nvim_buf_get_lines(terminal_buf, 0, -1, false)

			-- Clean up trailing empty lines
			while #lines > 0 and lines[#lines] == "" do
				table.remove(lines)
			end

			table.insert(lines, "")
			table.insert(lines, "----------------------------------------")
			table.insert(lines, string.format("Exit code: %d", status))
			table.insert(lines, string.format("Time: ~%.3fs", duration))

			vim.schedule(function()
				if not manager.instances[id] then
					return
				end

				local old_win = manager.instances[id].win
				local new_buf = vim.api.nvim_create_buf(false, true)

				vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, lines)
				vim.api.nvim_buf_set_name(new_buf, buf_name .. "_result")
				vim.b[new_buf].oz_cmd = cmd
				vim.b[new_buf].oz_cwd = final_oz_cwd
				vim.bo[new_buf].filetype = "oz_term"
				vim.bo[new_buf].buftype = "nofile"
				vim.bo[new_buf].bufhidden = "hide"
				vim.bo[new_buf].modifiable = false

				-- Update manager with new buffer
				manager.instances[id].buf = new_buf
				vim.b[new_buf].oz_term_id = id
				manager.setup_buf_cleanup(id, new_buf)

				-- If the window is still valid, switch to the new buffer
				if old_win and vim.api.nvim_win_is_valid(old_win) then
					vim.api.nvim_win_set_buf(old_win, new_buf)
					local line_count = vim.api.nvim_buf_line_count(new_buf)
					vim.api.nvim_win_set_cursor(old_win, { line_count, 0 })
				end

				-- Finally delete the old terminal buffer
				if vim.api.nvim_buf_is_valid(terminal_buf) then
					vim.api.nvim_buf_delete(terminal_buf, { force = true })
				end
			end)
		end,
	})

	if opts.stdin then
		vim.fn.chansend(job_id, opts.stdin)
	end
end

return M
