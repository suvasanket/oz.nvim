local M = {}

local util = require("oz.util")

--- cmd parser
---@param cmd string
---@return table
function M.grep_cmd_parser(cmd)
	local tokens = {}
	for token in cmd:gmatch("%S+") do
		table.insert(tokens, token)
	end

	local result = {
		exe = tokens[1] or "",
		flags = {},
		pattern = "",
		target = nil,
	}

	local non_flag_tokens = {}

	for i = 2, #tokens do
		local token = tokens[i]
		if token:sub(1, 1) == "-" then
			table.insert(result.flags, token)
		else
			table.insert(non_flag_tokens, token)
		end
	end

	if #non_flag_tokens >= 1 then
		local pat = non_flag_tokens[1]
		pat = pat:gsub("^[\"']", ""):gsub("[\"']$", "")
		result.pattern = pat
	end

	if #non_flag_tokens >= 2 then
		result.target = non_flag_tokens[2]
	end

	return result
end

-- check if cmd is grep or not
function M.cmd_contains_grep(cmd)
	local grep_commands = { "rg", "grep" }

	for _, grep_cmd in ipairs(grep_commands) do
		local pattern = string.format("^%s%%f[%%W]", grep_cmd)
		if cmd:match(pattern) then
			return true
		end
	end
	return false
end

--- grep -> qf
---@param cmd string
---@param dir string
function M.grep_to_qf(cmd, dir)
	local parsed = M.grep_cmd_parser(cmd) --REMOVE me
	local flags = parsed.flags
	local exe = parsed.exe
	local target = dir or parsed.target or "."

	local rg_flags = { "--vimgrep", "--color=never", "--no-heading" }
	local grep_flags = { "-nrH", "--color=never" }

	if exe == "rg" then
		M.oz_grep(exe, parsed.pattern, target, {
			flags = vim.tbl_deep_extend("keep", rg_flags, flags),
			formatter = "%f:%l:%c:%m",
		})
	elseif exe == "grep" then
		M.oz_grep(exe, parsed.pattern, target, {
			flags = vim.tbl_deep_extend("keep", grep_flags, flags),
			formatter = "%f:%l:%m",
		})
	end
end

--- show win
---@param lines string[]
local function grep_win(lines)
	util.create_win("grep_err", {
		content = lines,
		win_type = "bot 7",
		callback = function(buf_id)
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.opt_local.fillchars:append({ eob = " " })
			local shell_name = vim.fn.fnamemodify(vim.fn.environ()["SHELL"] or vim.fn.environ()["COMSPEC"], ":t:r")

			if shell_name == "bash" or shell_name == "zsh" then
				vim.bo.ft = "sh"
			elseif shell_name == "powershell" then
				vim.bo.ft = "ps1"
			else
				vim.bo.ft = shell_name
			end

			vim.keymap.set("n", "q", "<cmd>close<cr>", { desc = "close", buffer = buf_id })
		end,
	})
end

--- oz grep
---@param cmd string
---@param pattern string|table
---@param dir string
---@param opts {flags: string[], formatter: string, title: string}
function M.oz_grep(cmd, pattern, dir, opts)
	opts = opts or {}
	local formatter = opts.formatter
	local args = {}

	if opts.flags then
		for _, a in ipairs(opts.flags) do
			table.insert(args, a)
		end
	end

	table.insert(args, pattern)
	if dir then
		table.insert(args, dir)
	end

	local stdout_lines = {}
	local stderr_lines = {}

	---@diagnostic disable-next-line: deprecated
	local grep_shellcmd = { cmd, unpack(args) }
	-- print(vim.inspect(grep_shellcmd))
	vim.fn.jobstart(grep_shellcmd, {
		stdout_buffered = true,
		on_stdout = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(stdout_lines, line)
					end
				end
			end
		end,
		on_stderr = function(_, data, _)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(stderr_lines, line)
					end
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			if exit_code == 0 then
				vim.fn.setqflist({}, " ", {
					lines = stdout_lines,
					efm = formatter,
					title = opts.title or pattern,
				})
				if #vim.fn.getqflist() == 1 then
					vim.cmd("cfirst")
				elseif #vim.fn.getqflist() > 0 then
					vim.cmd("cw")
				end
			else
				if #stderr_lines > 0 then
					grep_win(stderr_lines)
				elseif #stderr_lines > 0 then
					grep_win(stdout_lines)
				else
					util.Notify("No matches found", "warn", "oz_grep")
				end
			end
		end,
	})
end

-- parse the arg_string
local function parse_usercmd_argstring(argstring)
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

-- parse :Grep args
---@param args table
---@return string
---@return any
---@return nil
local function parse_args(args)
	args = type(args) == "string" and parse_usercmd_argstring(args) or args

	local flags = ""
	local idx = 1

	while args[idx] and args[idx]:match("^%-%-?") do
		flags = flags .. args[idx] .. " "
		idx = idx + 1
	end

	flags = flags:match("^%s*(.-)%s*$")
	assert(args[idx], "A pattern is required")
	local pattern = args[idx]
	local target_dir = args[idx + 1] or nil

	pattern = string.gsub(pattern, "^(['\"])(.*)%1$", "%2")

	if target_dir and target_dir:find("%%") then
		target_dir = vim.fn.expand(target_dir)
	end

	return pattern, flags, target_dir
end

--- escape pattern NOTE: yeah i know about -F
---@param str any
---@return string
local function escape_pattern(str)
	-- Escape regex special characters using a pattern that matches any of them
	local special_chars = "[%.%*%+%?%(%)%[%]%{%}%^%$\\|]"
	local escaped = str:gsub(special_chars, "\\%0")

	-- Escape double quotes for shell compatibility
	escaped = escaped:gsub('"', '\\"')

	-- Escape other shell-sensitive characters (e.g., !, `)
	escaped = escaped:gsub("!", "\\!")
	escaped = escaped:gsub("`", "\\`")

	return escaped
end

-- :Grep init
function M.oz_grep_init(config)
	-- Grep usercmd
	vim.api.nvim_create_user_command("Grep", function(opts)
		local pattern, flags, target_dir
		if opts.range ~= 0 then
			pattern = escape_pattern(util.get_visual_selection())
			target_dir = opts.fargs[1] -- if taking from range then use the first arg as target_dir
		else
			pattern, flags, target_dir = parse_args(opts.args) -- NOTE: opts.fargs won't work
		end

		-- parse the usercmd args.
		local project_root = util.GetProjectRoot()

		if opts.bang then
			target_dir = vim.fn.getcwd()
		elseif not target_dir then
			target_dir = (vim.bo.ft == "oil" and require("oil").get_current_dir()) or (project_root or vim.fn.getcwd())
		end

		local grep_opt = vim.o.grepprg
		if not grep_opt then
			if vim.fn.executable("rg") == 1 then
				grep_opt = "rg"
			else
				grep_opt = "grep"
			end
		end
		-- parse the user option grepprg.
		local parsed_opt = M.grep_cmd_parser(grep_opt)
		local opt_flags = parsed_opt.flags
		local opt_exe = parsed_opt.exe
		local grep_fm = vim.o.grepformat

		-- add appropriate flags and efm
		local grep_flags = { "-nrH", "--color=never" }
		local rg_flags = { "--vimgrep", "--color=never", "--no-heading" }
		if opt_exe == "rg" then
			opt_flags = vim.tbl_deep_extend("force", rg_flags, opt_flags)
			grep_fm = "%f:%l:%c:%m"
		elseif opt_exe == "grep" then
			opt_flags = vim.tbl_deep_extend("force", grep_flags, opt_flags)
			grep_fm = "%f:%l:%m"
		end

		-- if flags passed as args
		if flags ~= "" then
			table.insert(opt_flags, flags)
		end

		M.oz_grep(opt_exe, pattern, target_dir, {
			flags = opt_flags,
			formatter = grep_fm,
		})
	end, {
		-- nargs = "+",
		nargs = "*",
		complete = "file",
		bang = true,
		range = true,
		desc = "async oz_grep.",
	})

	-- override grep
	if config.override_grep then
		vim.cmd([[
            cnoreabbrev <expr> grep getcmdtype() == ':' && getcmdline() ==# 'grep' ? 'Grep' : 'grep'
        ]])
	end
end

return M
