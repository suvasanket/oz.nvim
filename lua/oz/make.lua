local M = {}
local util = require("oz.util")
local m_util = require("oz.mappings.util")

function M.Make_func(args)
	local cmd = m_util.detect_makeprg(vim.fn.expand("%"))
	local output = {}

	if args ~= "" then
		cmd = cmd .. " " .. args
	end

	local cmd_parts = vim.split(cmd, "%s+")

	-- Start the job
	local job_id = vim.fn.jobstart(cmd_parts, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output, line)
				end
			end
		end,
		on_stderr = function(_, data, _)
			-- Collect stderr lines
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output, line)
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			local tempfile = vim.fn.tempname()
			vim.fn.writefile(output, tempfile)

			vim.cmd("cfile " .. tempfile)

			if #vim.fn.getqflist() > 0 then
				vim.cmd("copen | cfirst")
			else
				vim.cmd("cclose")
				util.echoprint("oz: Command executed successfully! (exit_code:" .. exit_code .. ")")
			end

			vim.fn.delete(tempfile)
		end,
	})

	if job_id <= 0 then
		util.echoprint("oz: Failed to start job", "ErrorMsg")
	else
		print("oz: Job started with ID: " .. job_id)
	end
end

function M.asyncmake_init(config)
	-- Make cmd
	vim.api.nvim_create_user_command("Make", function(opts)
		M.Make_func(opts.args)
	end, { nargs = "*", desc = "oz: async make" })

    -- override make
	if config.override_make then
		vim.cmd([[cnoreabbrev make Make]])
	end
end

return M
