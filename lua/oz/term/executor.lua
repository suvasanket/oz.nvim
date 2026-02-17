local M = {}

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
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
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
		local readable_cache = {}

		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

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

					-- Fast path: if it contains : or (, it might be an EFM match
					local maybe_efm = text:find("[:(]") ~= nil
					local full_path = text

					if maybe_efm then
						-- Only call getqflist if it looks like an EFM match to save performance
						local sub_qf = vim.fn.getqflist({ lines = { text }, efm = efm })
						local sub_entry = sub_qf.items and sub_qf.items[1]

						if sub_entry and sub_entry.valid == 1 then
							full_path = sub_entry.filename
							if (not full_path or full_path == "") and sub_entry.bufnr > 0 then
								full_path = vim.api.nvim_buf_get_name(sub_entry.bufnr)
							end
						end
					end

					if full_path and full_path ~= "" then
						if not (full_path:match("^/") or full_path:match("^%a:")) then
							full_path = oz_cwd .. "/" .. full_path
						end

						if util.is_readable(full_path, readable_cache) then
							vim.api.nvim_buf_add_highlight(buf, ns, "@attribute", i - 1, start_pos, end_pos)
						end
					end
					start_idx = end_pos
				end
			end
		end
	end)
end

local function apply_win_styling(win, buf)
	if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local cmd = vim.b[buf].oz_cmd or ""
	local wo = vim.wo[win]
	wo.number = false
	wo.relativenumber = false
	wo.signcolumn = "no"
	wo.wrap = false
	wo.spell = false
	wo.list = false
	wo.winbar = string.format("$ %s", cmd)
end

local group = vim.api.nvim_create_augroup("oz_term_setup", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	pattern = "oz_term",
	group = group,
	callback = function(ev)
		local buf = ev.buf
		highlight(buf)
		require("oz.term.keymaps").setup(buf)
		vim.schedule(function()
			local win = vim.fn.bufwinid(buf)
			if win ~= -1 then
				apply_win_styling(win, buf)
			end
		end)
	end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
	pattern = "*",
	group = group,
	callback = function(ev)
		if vim.bo[ev.buf].filetype == "oz_term" then
			local win = vim.api.nvim_get_current_win()
			apply_win_styling(win, ev.buf)
		end
	end,
})

--- run
---@param cmd string shell cmd
---@param opts {cwd: string, stdin: string, hidden: boolean}? runs the cmd then put the stdout into a buffer
function M.run(cmd, opts)
	if not cmd or cmd == "" then
		return
	end
	cmd = vim.fn.expandcmd(cmd)
	opts = opts or {}
	local manager = require("oz.term.manager")
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
	local start_cwd = opts.cwd or vim.fn.getcwd()
	if not (start_cwd:match("^/") or start_cwd:match("^%a:")) then
		start_cwd = vim.fn.fnamemodify(start_cwd, ":p")
	end
	if start_cwd:sub(-1) == "/" or start_cwd:sub(-1) == "\\" then
		start_cwd = start_cwd:sub(1, -2)
	end
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

	local terminal_buf, job_id

	local function setup_terminal(buf, win_id)
		vim.api.nvim_buf_call(buf, function()
			if opts.cwd then
				pcall(vim.cmd, "lcd " .. vim.fn.fnameescape(start_cwd))
			end

			if win_id then
				vim.cmd("terminal " .. cmd)
				job_id = vim.b[buf].terminal_job_id
			else
				job_id = vim.fn.termopen(cmd)
			end

			vim.api.nvim_buf_set_name(buf, buf_name)
			vim.b[buf].oz_cmd = cmd
			vim.b[buf].oz_cwd = oz_cwd
			vim.bo[buf].filetype = "oz_term"

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
		end)
	end

	if opts.hidden then
		terminal_buf = vim.api.nvim_create_buf(false, true)
		setup_terminal(terminal_buf, nil)
	else
		-- create a new window or reuse existing
		require("oz.util").create_win("oz_term", {
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

				if reuse_win then
					terminal_buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_win_set_buf(win_id, terminal_buf)
				else
					terminal_buf = vim.api.nvim_get_current_buf()
				end

				setup_terminal(terminal_buf, win_id)

				-- Delete scratch buffer created by create_win if it's different
				if terminal_buf ~= buf_id and vim.api.nvim_buf_is_valid(buf_id) then
					pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
				end
			end,
		})
	end

	-- Update job status when terminal finishes
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = terminal_buf,
		once = true,
		callback = function(ev)
			local end_time = (vim.uv or vim.loop).hrtime()
			local duration = (end_time - start_time) / 1e9
			local status = vim.v.event.status
			local t_buf = ev.buf
			local final_oz_cwd = vim.b[t_buf].oz_cwd

			if manager.instances[id] then
				manager.instances[id].job_active = false
			end

			-- Capture lines before deleting buffer
			local lines = vim.api.nvim_buf_get_lines(t_buf, 0, -1, false)

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
				if vim.api.nvim_buf_is_valid(t_buf) then
					vim.api.nvim_buf_delete(t_buf, { force = true })
				end
			end)
		end,
	})

	if opts.stdin then
		vim.fn.chansend(job_id, opts.stdin)
	end
end

return M
