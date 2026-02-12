local M = {}

M.cached_cmd = nil
M.term_cmd_ft = nil

local function term_cmd_init()
	local function complete(arg_lead)
		local manager = require("oz.term.manager")
		local ids = {}
		for id, _ in pairs(manager.instances) do
			local sid = tostring(id)
			if sid:find("^" .. arg_lead) then
				table.insert(ids, sid)
			end
		end
		return ids
	end

	vim.api.nvim_create_user_command("Term", function(args)
		local opts = { hidden = args.bang }
		-- args
		if args.args and #args.args > 0 then
			M.cached_cmd = args.args
			M.term_cmd_ft = vim.bo.ft
			require("oz.term.manager").run_with_arg(args.args, opts)
		else
            local type = args.bang and "Term!" or "Term"
			require("oz.term.cmd_wizard").cmd_func(type, function(user_input)
				M.cached_cmd = user_input
				M.term_cmd_ft = vim.bo.ft
				require("oz.term.manager").run_with_arg(user_input, opts)
			end)
		end
	end, { nargs = "*", bang = true, desc = "oz_term", complete = "shellcmd" })

	vim.api.nvim_create_user_command("TermToggle", function(args)
		require("oz.term.manager").toggle(args.args ~= "" and args.args or nil)
	end, { nargs = "?", complete = complete, desc = "toggle oz_term" })

	vim.api.nvim_create_user_command("TermClose", function(args)
		require("oz.term.manager").close(args.args ~= "" and args.args or nil)
	end, { nargs = "?", complete = complete, desc = "close oz_term" })
end

function M.Term_init(_)
	term_cmd_init()
end

function M.run_in_term(cmd, dir)
	local opts = { cwd = dir }
	M.cached_cmd = cmd
	M.term_cmd_ft = vim.bo.ft
	require("oz.term.manager").run_with_arg(cmd, opts)
end

-- Export manager functions for convenience (lazy-loaded)
M.toggle_term = function(...)
	return require("oz.term.manager").toggle(...)
end
M.close_term = function(...)
	return require("oz.term.manager").close(...)
end
M.run_with_arg = function(...)
	return require("oz.term.manager").run_with_arg(...)
end

return M
