local M = {}
local util = require("oz.util")
local original_mappings = {}

function M.expand_expressions(str)
	local pattern = "%%[:%w]*"

	local expanded_str = string.gsub(str, pattern, function(exp)
		return vim.fn.expand(exp)
	end)

	return expanded_str
end

function M.parse_args(argstring)
	local args = {}
	local i = 1
	local len = #argstring

	while i <= len do
		while i <= len and argstring:sub(i, i):match("%s") do
			i = i + 1
		end
		if i > len then
			break
		end
		if argstring:sub(i, i) == '"' or argstring:sub(i, i) == "'" then
			local quote = argstring:sub(i, i)
			local start = i + 1
			i = i + 1
			while i <= len and argstring:sub(i, i) ~= quote do
				i = i + 1
			end

			if i <= len then
				table.insert(args, argstring:sub(start, i - 1))
				i = i + 1
			else
				table.insert(args, argstring:sub(start))
			end
		else
			local start = i
			while i <= len and not argstring:sub(i, i):match("%s") do
				i = i + 1
			end

			table.insert(args, argstring:sub(start, i - 1))
		end
	end

	return args
end

function M.save_lines_to_commitfile(lines)
	local git_dir_command = "git rev-parse --git-dir 2>/dev/null"
	local git_dir = vim.fn.system(git_dir_command):gsub("%s+$", "")

	if vim.v.shell_error ~= 0 then
		return
	end

	local commit_msg_file = git_dir .. "/COMMIT_EDITMSG"

	local file = io.open(commit_msg_file, "w")
	if file then
		-- Write all lines to the file
		for _, line in ipairs(lines) do
			file:write(line .. "\n")
		end
		file:close()
	end
end

function M.set_cmdline(str)
	local cmdline = str:gsub("%|", "")
	vim.api.nvim_feedkeys(":" .. cmdline, "n", false)
	local cursor_pos = str:find("%|")
	if cursor_pos then
		vim.api.nvim_input(string.rep("<Left>", #str - cursor_pos))
	end
end

function M.if_in_git()
	local res = util.ShellOutputList("git rev-parse --is-inside-work-tree 2>/dev/null")
	res = vim.trim(res[1])
	if res:find("true") then
		return true
	else
		return false
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
	vim.api.nvim_set_hl(0, "OzGitTermPlus", { fg = "#000000", bg = "#A0C878" })
	vim.api.nvim_set_hl(0, "OzGitTermMinus", { fg = "#000000", bg = "#E17564" })
	vim.fn.matchadd("OzGitTermPlus", "^+.*$", 0, -1, { extend = true })
	vim.fn.matchadd("OzGitTermMinus", "^-.*$", 0, -1, { extend = true })
end

function M.run_term_cmd(args)
	local editor_env = vim.fn.getenv("VISUAL")
	if not args.cmd then
		return
	end

	vim.fn.setenv("VISUAL", "nvr -O") -- FIXME check if nvr installed or not then set.
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
        callback = function ()
            vim.cmd("startinsert")
        end
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

return M
