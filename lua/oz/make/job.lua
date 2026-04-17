local M = {}
local util = require("oz.util")
local efm = require("oz.make.efm")

M.current_job_id = nil
M.jobs = {}

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
	local cmd_tbl = util.parse_args(arg_str)
	local make_cmd = require("oz.make.auto").get_makeprg(dir)

	if vim.bo.makeprg == "" then
		local detected_cmd = require("oz.make.detect").get_build_command(dir or util.GetProjectRoot())
		if detected_cmd and make_cmd ~= detected_cmd then
			make_cmd = detected_cmd
		end
	end

	local make_cmd_tbl = util.parse_args(make_cmd)
	for i = #make_cmd_tbl, 1, -1 do
		table.insert(cmd_tbl, 1, make_cmd_tbl[i])
	end

	local output = {}

	-- progress stuff
	local pro_title = table.concat(cmd_tbl, " ")
	local u_id = util.generate_unique_id()
	util.start_progress(u_id, { title = pro_title, fidget_lsp = "oz_make" })

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
				require("oz.make.win").refresh_makeout_win(output)
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
				require("oz.make.win").refresh_makeout_win(output)
			end
		end,
		on_exit = function(jobid, exit_code, _)
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
			util.stop_progress(u_id, {
				exit_code = exit_code,
				title = pro_title,
				message = { "Build completed successfully", "Error occured while building" },
			})

			local has_qf = efm.capture_lines_to_qf(output, jobid)
			local qf_count = #vim.fn.getqflist()

			if has_qf and qf_count > 0 then
				vim.cmd("copen | cfirst")
			elseif exit_code ~= 0 then
				require("oz.make.win").makeout_win(output, pro_title, dir)
			elseif qf_count == 0 then
				vim.cmd("cclose")
			end
		end,
	})

	if ok and job_id > 0 then
		M.current_job_id = job_id
		M.jobs[job_id] = { cwd = dir, ft = vim.bo.ft }
		local mappings = config.transient_mappings
		if mappings then
			local msg_parts = {}
			if mappings.kill_job then
				vim.keymap.set("n", mappings.kill_job, M.kill_make_job, { desc = "[oz_make]Kill make job", silent = true })
				table.insert(msg_parts, string.format("%s: cancel", mappings.kill_job))
			end
			if mappings.toggle_output then
				vim.keymap.set("n", mappings.toggle_output, function()
					require("oz.make.win").makeout_win(output, pro_title, dir)
				end, { desc = "[oz_make]Toggle output", silent = true })
				table.insert(msg_parts, string.format("%s: show output", mappings.toggle_output))
			end

			if #msg_parts > 0 then
				util.Notify("Try " .. table.concat(msg_parts, " , "), "info", "oz_make", true)
			end
		end
	elseif not ok or job_id <= 0 then
		util.Notify("Incorrect makeprg: " .. make_cmd, "error", "oz_make")
		util.stop_progress(u_id, {
			title = pro_title,
			message = { "Build completed successfully", "Error occured while building" },
		})
		return
	end
end

return M
