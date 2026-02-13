local M = {}

M.cached_cmd = nil
M.term_cmd_ft = nil

local function term_cmd_init(config)
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
		local prefix = config.root_prefix
		-- args
		if args.args and #args.args > 0 then
			local cmd = args.args
			if prefix and cmd:sub(1, #prefix) == prefix then
				cmd = cmd:sub(#prefix + 1)
				opts.cwd = require("oz.util").GetProjectRoot()
			end
			M.cached_cmd = cmd
			M.term_cmd_ft = vim.bo.ft
			require("oz.term.manager").run_with_arg(cmd, opts)
		else
			local type = args.bang and "Term!" or "Term"
			require("oz.term.cmd_wizard").cmd_func(type, function(user_input)
				local cmd = user_input
				if prefix and cmd:sub(1, #prefix) == prefix then
					cmd = cmd:sub(#prefix + 1)
					opts.cwd = require("oz.util").GetProjectRoot()
				end
				M.cached_cmd = cmd
				M.term_cmd_ft = vim.bo.ft
				require("oz.term.manager").run_with_arg(cmd, opts)
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

function M.Term_init(config)
	term_cmd_init(config)
	if config and config.efm then
		local util = require("oz.term.util")
		local seen = {}
		local combined = {}
		for _, p in ipairs(config.efm) do
			if p ~= "" and not seen[p] then
				table.insert(combined, p)
				seen[p] = true
			end
		end
		for _, p in ipairs(util.EFM_PATTERNS) do
			if not seen[p] then
				table.insert(combined, p)
				seen[p] = true
			end
		end
		util.EFM_PATTERNS = combined
	end
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
