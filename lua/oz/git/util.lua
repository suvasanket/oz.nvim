--- @class oz.git.util
local M = {}
local original_mappings = {}
local util = require("oz.util")

--- Check if a path is inside a Git work tree.
--- @param path? string
--- @return boolean
function M.if_in_git(path)
	return util.if_in_git(path)
end

--- Jump to a string in the current buffer.
--- @param str string
function M.goto_str(str)
	local saved_pos = vim.fn.getpos(".")
	vim.cmd("keepjumps normal! gg")
	local line_num = vim.fn.search(str, "W")

	if line_num == 0 then
		vim.fn.setpos(".", saved_pos)
	end
end

--- Temporarily remap a key.
--- @param mode string
--- @param lhs string
--- @param new_rhs string|function
--- @param opts? table
function M.temp_remap(mode, lhs, new_rhs, opts)
	opts = opts or {}
	original_mappings[mode .. lhs] = {
		rhs = vim.fn.maparg(lhs, mode),
		opts = vim.fn.maparg(lhs, mode, false, true) or {},
	}

	vim.keymap.set(mode, lhs, new_rhs, opts)
end

--- Restore a temporarily remapped key.
--- @param mode string
--- @param lhs string
function M.restore_mapping(mode, lhs)
	local key = mode .. lhs
	if original_mappings[key] then
		if original_mappings[key].rhs == "" then
			vim.keymap.del(mode, lhs)
		else
			local opts = original_mappings[key].opts
			opts.noremap = nil -- Remove this as it's handled by vim.keymap.set
			vim.keymap.set(mode, lhs, original_mappings[key].rhs, opts)
		end
		original_mappings[key] = nil
	end
end

--- Set a keymap.
--- @param mode string|string[]
--- @param lhs string|string[]
--- @param rhs string|function
--- @param opts? table
function M.map(mode, lhs, rhs, opts)
	local options = { silent = true, remap = false }
	if type(lhs) == "string" and #lhs ~= 1 then
		options.nowait = true
	end
	if opts then
		options = vim.tbl_extend("force", options, opts)
	end

	if type(lhs) == "table" then
		for _, key in ipairs(lhs) do
			vim.keymap.set(mode, key, rhs, options)
		end
	else
		vim.keymap.set(mode, lhs, rhs, options)
	end
end

--- Check if a string contains a Git hash.
--- @param text string
--- @return boolean
function M.str_contains_hash(text)
	return util.str_contains_hash(text)
end

--- Apply terminal highlighting for diffs.
local function term_highlight()
	vim.cmd("syntax clear")

	vim.cmd([[
        syntax match @diff.delta /^@@ .\+@@/
        syntax match @diff.plus /^+.\+$/
        syntax match @diff.minus /^-.\+$/
        syntax match @field /^diff --git .\+$/
        syntax match @field /^\(---\|+++\) .\+$/
    ]])
end

--- Run a command in a terminal buffer.
--- @param args {cmd: string, open_in?: string, on_exit_callback?: function}
function M.run_term_cmd(args)
	local editor_env = vim.fn.getenv("VISUAL")
	if not args.cmd then
		return
	end

	if vim.fn.executable("nvr") == 1 then
		vim.fn.setenv("VISUAL", "nvr -O")
	end
	vim.cmd(args.open_in or "tabnew")
	vim.cmd("term " .. args.cmd)

	local term_buf_id = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(term_buf_id, string.format("oz_git://%s", args.cmd or "no_cmd"))

	vim.api.nvim_buf_call(term_buf_id, function()
		vim.cmd("startinsert")
		term_highlight()
	end)

	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = term_buf_id,
		callback = function()
			vim.cmd("startinsert")
		end,
	})

	vim.api.nvim_create_autocmd("TermClose", {
		buffer = term_buf_id,
		callback = function(event)
			vim.api.nvim_buf_delete(term_buf_id, { force = true })
			if args.on_exit_callback then
				args.on_exit_callback(event)
			end
			vim.fn.setenv("VISUAL", editor_env)
		end,
	})
end

--- Create one or more user commands.
--- @param commands string|string[]
--- @param func string|function
--- @param opts? table
function M.User_cmd(commands, func, opts)
	if type(commands) == "string" then
		vim.api.nvim_create_user_command(commands, func, opts)
	elseif type(commands) == "table" then
		for _, command in pairs(commands) do
			vim.api.nvim_create_user_command(command, func, opts)
		end
	else
		error("commands must be a string or a table")
	end
end

--- Get the Git project root.
--- @return string|nil
function M.get_project_root()
	local state = require("oz.git").state
	if state and state.root then
		return state.root
	end

	local root = util.get_git_root()
	if root then
		if state then
			state.root = root
		end
		return root
	else
		return util.GetProjectRoot()
	end
end

--- Get a list of branches.
--- @param arg? {loc?: boolean, rem?: boolean}
--- @return string[]
function M.get_branch(arg)
	return util.get_branch(arg)
end

return M
