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
		-- Skip leading whitespace
		while i <= len and argstring:sub(i, i):match("%s") do
			i = i + 1
		end
		if i > len then
			break
		end

		local start_char = argstring:sub(i, i)

		if start_char == '"' or start_char == "'" then
			-- Handle quoted arguments
			local quote = start_char
			local start = i + 1
			i = i + 1 -- Move past opening quote
			local found_quote = false
			while i <= len do
				if argstring:sub(i, i) == quote then
					found_quote = true
					break
				end
				i = i + 1
			end

			if found_quote then
				table.insert(args, argstring:sub(start, i - 1))
				i = i + 1 -- Move past closing quote
			else
				table.insert(args, argstring:sub(start)) -- Unterminated
			end
		else
			-- Handle non-quoted arguments (potentially with key='value')
			local start = i
			local end_pos = -1 -- Position *after* the argument ends

			local scan_pos = i
			while scan_pos <= len do
				local char = argstring:sub(scan_pos, scan_pos)

				if char:match("%s") then
					end_pos = scan_pos -- Argument ends before the space
					break
				elseif char == "=" then
					if scan_pos + 1 <= len then
						local next_char = argstring:sub(scan_pos + 1, scan_pos + 1)
						if next_char == '"' or next_char == "'" then
							-- Found key='value', find end of quoted value
							local value_quote = next_char
							local quote_end_scan = scan_pos + 2
							while
								quote_end_scan <= len
								and argstring:sub(quote_end_scan, quote_end_scan) ~= value_quote
							do
								quote_end_scan = quote_end_scan + 1
							end

							if quote_end_scan <= len then
								end_pos = quote_end_scan + 1 -- Argument ends *after* the closing quote
							else
								end_pos = len + 1 -- Unterminated value quote, arg ends at string end
							end
							break -- Definitively found end for this key='value' argument
						else
							scan_pos = scan_pos + 1 -- '=' not followed by quote
						end
					else
						scan_pos = scan_pos + 1 -- '=' is last char
					end
				else
					scan_pos = scan_pos + 1 -- Normal character
				end
			end

			if end_pos == -1 then -- Loop finished without break (reached end of string)
				end_pos = len + 1
			end

			table.insert(args, argstring:sub(start, end_pos - 1))
			i = end_pos -- Update main loop iterator for next argument
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
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(":<C-U>" .. cmdline, true, false, true), "n", false)
	local cursor_pos = str:find("%|")
	if cursor_pos then
		vim.api.nvim_input(string.rep("<Left>", #str - cursor_pos))
	end
end

function M.if_in_git()
	local res = util.ShellOutputList("git rev-parse --is-inside-work-tree 2>/dev/null")
	if #res > 0 then
		res = vim.trim(res[1])
		if res:find("true") then
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

return M
