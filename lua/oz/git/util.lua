local M = {}
local original_mappings = {}
local util = require("oz.util")
local shell = require("oz.util.shell")

function M.if_in_git(path)
	local ok, output = shell.run_command({ "git", "rev-parse", "--is-inside-work-tree" }, path)

	if ok then
		if output[1]:find("true") then
			return true
		else
			return false
		end
	end
end

function M.goto_str(str)
	local saved_pos = vim.fn.getpos(".")
	vim.cmd("keepjumps normal! gg")
	local line_num = vim.fn.search(str, "W")

	if line_num == 0 then
		vim.fn.setpos(".", saved_pos)
	end
end

function M.temp_remap(mode, lhs, new_rhs, opts)
	opts = opts or {}
	original_mappings[mode .. lhs] = {
		rhs = vim.fn.maparg(lhs, mode),
		opts = vim.fn.maparg(lhs, mode, false, true) or {},
	}

	vim.keymap.set(mode, lhs, new_rhs, opts)
end

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

function M.map(mode, lhs, rhs, opts)
	local options = { silent = true, remap = false }
	if #lhs ~= 1 then
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

function M.str_contains_hash(text)
	if type(text) ~= "string" then
		return false
	end

	for hex_sequence in text:gmatch("(%x+)") do
		local len = #hex_sequence -- Get the length of the found sequence
		if (len >= 7 and len <= 12) or len == 40 or len == 64 then
			return true
		end
	end
	return false
end

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

function M.get_project_root()
	local ok, path = shell.run_command({ "git", "rev-parse", "--show-toplevel" })
	if ok and #path ~= 0 then
		local joined_path = table.concat(path, " ")
		vim.trim(joined_path)
		require("oz.git").state.root = joined_path

		return joined_path
	else
		return util.GetProjectRoot()
	end
end

--- get branches
---@param arg {loc: boolean|nil, rem: boolean|nil, all: boolean|nil}|nil
---@return table
function M.get_branch(arg)
	local ref
	if arg and arg.loc then
		ref = "refs/heads"
	elseif arg and arg.rem then
		ref = "refs/remotes"
	else
		ref = "refs/heads refs/remotes"
	end
	return shell.shellout_tbl(string.format("git for-each-ref --format=%%(refname:short) %s", ref))
end

return M
