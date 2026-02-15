local M = {}
local util = require("oz.util")
local arg_parser = require("oz.util.parse_args")
local efm = require("oz.make.efm")
local progress = require("oz.util.progress")

M.current_job_id = nil

--- check if its just wranings
---@param needle string
---@return boolean
local function all_contains(needle)
	local MAX_LEN = 50
	if not needle or needle == "" then
		return false
	end

	local qfl = vim.fn.getqflist()
	if #qfl > MAX_LEN or #qfl < 1 then
		return false
	end

	local nl = needle:lower()
	for i = 1, #qfl do
		local item = qfl[i]
		local text = item.text or item.filename or tostring(item) -- fallback
		if not text or text == "" then
			return false
		end
		if not (type(text) == "string" and text:lower():find(nl, 1, true)) then
			return false
		end
	end
	return true
end

function M.kill_make_job()
	if M.current_job_id and M.current_job_id > 0 then
		vim.fn.jobstop(M.current_job_id)
		M.current_job_id = nil
		util.Notify("Make job killed", "info", "oz_make")
	else
		util.Notify("No running make job", "warn", "oz_make")
	end
end

function M.Make_func(arg_str, dir, config)
	if M.current_job_id and M.current_job_id > 0 then
		vim.fn.jobstop(M.current_job_id)
		M.current_job_id = nil
	end

	dir = dir or vim.fn.getcwd()
	local cmd_tbl = arg_parser.parse_args(arg_str)
	local make_cmd = vim.o.makeprg
	if make_cmd == "make" then
		local detected_cmd = require("oz.make.detect").get_build_command(dir or util.GetProjectRoot())
		if detected_cmd and make_cmd ~= detected_cmd then
			make_cmd = detected_cmd
		end
	end

	local make_cmd_tbl = arg_parser.parse_args(make_cmd)
	for i = #make_cmd_tbl, 1, -1 do
		table.insert(cmd_tbl, 1, make_cmd_tbl[i])
	end

	local output = {}
	local current_efm = vim.bo.errorformat
	local current_ft = vim.bo.ft

	-- progress stuff
	local pro_title = table.concat(cmd_tbl, " ")
	local u_id = util.generate_unique_id()
	progress.start_progress(u_id, { title = pro_title, fidget_lsp = "oz_make" })

	-- Start the job
	local ok, job_id = pcall(vim.fn.jobstart, cmd_tbl, {
		cwd = dir,
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data, _)
			local added = false
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output, line)
					added = true
				end
			end
			if added then
				-- Only refresh if the window is already open
				local wins = vim.api.nvim_list_wins()
				for _, win_id in ipairs(wins) do
					local buf = vim.api.nvim_win_get_buf(win_id)
					local ok, name = pcall(vim.api.nvim_buf_get_var, buf, "oz_win_name")
					if ok and name == "make_err" then
						require("oz.make.win").make_err_win(output, pro_title, dir)
						break
					end
				end
			end
		end,
		on_stderr = function(_, data, _)
			-- Collect stderr lines
			local added = false
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output, line)
					added = true
				end
			end
			if added then
				-- Only refresh if the window is already open
				local wins = vim.api.nvim_list_wins()
				for _, win_id in ipairs(wins) do
					local buf = vim.api.nvim_win_get_buf(win_id)
					local ok, name = pcall(vim.api.nvim_buf_get_var, buf, "oz_win_name")
					if ok and name == "make_err" then
						require("oz.make.win").make_err_win(output, pro_title, dir)
						break
					end
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			M.current_job_id = nil
			if config.transient_mappings then
				if config.transient_mappings.kill_job then
					pcall(vim.keymap.del, "n", config.transient_mappings.kill_job)
				end
				if config.transient_mappings.toggle_output then
					pcall(vim.keymap.del, "n", config.transient_mappings.toggle_output)
				end
			end

			-- progress stuff
			progress.stop_progress(u_id, {
				exit_code = exit_code,
				title = pro_title,
				message = { "Build completed successfully", "Error occured while building" },
			})

			efm.capture_lines_to_qf(output, current_ft, config.efm, true, current_efm, dir)

			if all_contains("warning") or all_contains("warn") then
				util.echoprint("Warning found: do :copen to see", "healthWarning")
			elseif #vim.fn.getqflist() == 1 then
				vim.cmd("cfirst")
			elseif #vim.fn.getqflist() > 0 then
				vim.cmd("cw | cfirst")
				util.echoprint("Issue found: resolve then continue", "healthError")
			else
				-- If exit_code is non-zero and no QF entries, show the raw output window
				if exit_code ~= 0 then
					util.Notify("Consult :help efm, then set error format.", "warn", "oz_make")
					if #output > 0 then
						require("oz.make.win").make_err_win(output, pro_title, dir)
					end
				else
					vim.cmd("cw")
				end
			end
		end,
	})

	if ok and job_id > 0 then
		M.current_job_id = job_id
		local mappings = config.transient_mappings
		if mappings then
			local msg_parts = {}
			if mappings.kill_job then
				util.Map("n", mappings.kill_job, M.kill_make_job, { desc = "[oz_make]Kill make job" })
				table.insert(msg_parts, string.format("%s: cancel", mappings.kill_job))
			end
			if mappings.toggle_output then
				util.Map("n", mappings.toggle_output, function()
					require("oz.make.win").make_err_win(output, pro_title, dir)
				end, { desc = "[oz_make]Toggle output" })
				table.insert(msg_parts, string.format("%s: show output", mappings.toggle_output))
			end

			if #msg_parts > 0 then
                util.Notify("Make running " .. table.concat(msg_parts, " , "), nil, "oz_make", true)
			end
		end
	elseif not ok or job_id <= 0 then
		util.Notify("Cannot create the job", "error", "oz_make")
		progress.stop_progress(u_id, {
			title = pro_title,
			message = { "Build completed successfully", "Error occured while building" },
		})
		return
	end
end

return M
