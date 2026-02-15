local M = {}
local util = require("oz.util")

function M.oz_make_init(config)
	M.config = config

	-- Make cmd
	vim.api.nvim_create_user_command("Make", function(arg)
		local job = require("oz.make.job")
		-- run make in cwd
		if arg.bang then
			job.Make_func(arg.args, vim.fn.getcwd(), M.config)
		else
			job.Make_func(arg.args, util.GetProjectRoot(), M.config) -- run make in project root
		end
	end, { nargs = "*", desc = "[oz_make]make", bang = true })

	-- MakeKill cmd
	vim.api.nvim_create_user_command("MakeKill", function()
		require("oz.make.job").kill_make_job()
	end, { desc = "[oz_make]kill make job" })

	-- Automake cmd
	vim.api.nvim_create_user_command("AutoMake", function(opts)
		require("oz.make.auto").automake_cmd(opts)
	end, {
		desc = "[oz_make]automake",
		nargs = "?",
		complete = function()
			return { "filetype", "file", "addarg", "disable" }
		end,
	})

	-- override make
	if config.override_make then
		vim.cmd([[
            cnoreabbrev <expr> make getcmdtype() == ':' && getcmdline() ==# 'make' ? 'Make' : 'make'
        ]])
	end

	-- auto save makeprg
	if config.autosave_makeprg then
		require("oz.make.auto").makeprg_autosave()
	end
end

return M
