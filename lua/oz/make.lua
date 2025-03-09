local M = {}
local util = require("oz.util")
local m_util = require("oz.mappings.util")
local qf = require("oz.qf")
local p = require("oz.caching")
local json_name = "makeprg"

M.previous_makeprg = vim.o.makeprg

local function inside_dir(dir)
	if not dir then
		return
	end
	local current_file = vim.fn.expand("%:p")
	return current_file:find(dir, 1, true) == 1 -- Check if it starts with target_dir
end

function M.Make_func(args, dir)
	local cmd = m_util.detect_makeprg(vim.fn.expand("%")) or "make"
	cmd = "sh -c " .. cmd
	local output = {}

	if args ~= "" then
		cmd = cmd .. " " .. args
	end

	local cmd_parts = vim.split(cmd, "%s+")

	-- Start the job
	local ok, job_id = pcall(vim.fn.jobstart, cmd_parts, {
		cwd = dir,
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
			qf.capture_lines_to_qf(output, vim.bo.ft)

			if #vim.fn.getqflist() > 0 then
				vim.cmd("copen | cfirst")
			else
				vim.cmd("cclose")
				util.echoprint("oz: Nothing in quickfixlist! (exit_code:" .. exit_code .. ")")
			end
		end,
	})

	if not ok then
		util.Notify("oz: Cannot execute make", "error", "Make")
		return
	end
	if job_id <= 0 then
		util.echoprint("oz: Failed to start Make", "ErrorMsg")
	else
		print("Make started..")
	end
end

-- auto save makeprg
function M.makeprg_autosave()
	-- get if option changed
	vim.api.nvim_create_autocmd("OptionSet", {
		pattern = "makeprg",
		callback = function()
			M.previous_makeprg = vim.o.makeprg
			local project_root = util.GetProjectRoot()
			if project_root then
				p.set_data(project_root, M.previous_makeprg, json_name)
			end
		end,
	})

	-- dynamic set makeprg
	vim.api.nvim_create_autocmd({ "DirChanged", "BufEnter" }, {
		callback = function()
			local project_root = util.GetProjectRoot()
			if inside_dir(project_root) then
				M.previous_makeprg = vim.o.makeprg
				local makeprg_cmd = p.get_data(project_root, json_name)
				if makeprg_cmd then
					vim.o.makeprg = makeprg_cmd
				end
			else
				vim.o.makeprg = M.previous_makeprg
			end
		end,
	})
end

function M.asyncmake_init(config)
	-- Make cmd
	vim.api.nvim_create_user_command("Make", function(arg)
		-- run make in cwd
		if arg.bang then
			M.Make_func(arg.args, nil)
		else
			M.Make_func(arg.args, util.GetProjectRoot()) -- run make in project root
		end
	end, { nargs = "*", desc = "oz: async make", bang = true })

	-- override make
	if config.override_make then
		vim.cmd([[
        cnoreabbrev <expr> make getcmdline() == 'make' ? 'Make' : 'make'
        ]])
	end

	-- auto save makeprg
	if config.autosave_makeprg then
		M.makeprg_autosave()
	end
end

return M
