local M = {}
local manager = require("oz.term.manager")

M.cached_cmd = nil
M.term_cmd_ft = nil

local function term_cmd_init()
	local function complete(arg_lead)
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
		local opts = {}
		-- args
		if args.args and #args.args > 0 then
			M.cached_cmd = args.args
			M.term_cmd_ft = vim.bo.ft
			manager.run_with_arg(args.args, opts)
		else
			require("oz.term.cmd_assist").cmd_func("Term", function(user_input)
				M.cached_cmd = user_input
				M.term_cmd_ft = vim.bo.ft
				manager.run_with_arg(user_input, opts)
			end)
		end
	end, { nargs = "*", bang = true, desc = "oz_term", complete = "shellcmd" })

	vim.api.nvim_create_user_command("TermToggle", function(args)
		manager.toggle(args.args ~= "" and args.args or nil)
	end, { nargs = "?", complete = complete, desc = "toggle oz_term" })

	vim.api.nvim_create_user_command("TermClose", function(args)
		manager.close(args.args ~= "" and args.args or nil)
	end, { nargs = "?", complete = complete, desc = "close oz_term" })
end

function M.Term_init(config)
	term_cmd_init()
end

function M.run_in_term(cmd, dir)
	local opts = { cwd = dir }
	M.cached_cmd = cmd
	M.term_cmd_ft = vim.bo.ft
	manager.run_with_arg(cmd, opts)
end

-- Export manager functions for convenience
M.toggle_term = manager.toggle
M.close_term = manager.close
M.run_with_arg = manager.run_with_arg

return M
