local M = {}

---add to tbl with check
---@param tbl table
---@param item any
---@param pos integer|nil
---@return table
function M.tbl_insert(tbl, item, pos)
	if not vim.tbl_contains(tbl, item) then
		if pos then
			table.insert(tbl, pos, item)
		else
			table.insert(tbl, item)
		end
	end
	return tbl
end

--- get project root
---@param markers string[]|nil
---@param path_or_bufnr string|integer|nil
---@return nil
function M.GetProjectRoot(markers, path_or_bufnr)
	if markers then
		return vim.fs.root(path_or_bufnr or 0, markers) or nil
	end

	local patterns = { ".git", "Makefile", "Cargo.toml", "go.mod", "pom.xml", "build.gradle" }
	local root_fpattern = vim.fs.root(path_or_bufnr or 0, patterns)
	local workspace = vim.lsp.buf.list_workspace_folders()

	if root_fpattern then
		return root_fpattern
	elseif workspace then
		return workspace[#workspace]
	else
		return nil
	end
end

--- keymap
---@param mode string|table
---@param lhs string|table|nil
---@param rhs string|function
---@param opts table
function M.Map(mode, lhs, rhs, opts)
	if not lhs then
		return
	end
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

--- echo print
---@param str string
---@param hl string
function M.echoprint(str, hl)
	if not hl then
		hl = "MoreMsg"
	end
	vim.api.nvim_echo({ { str, hl } }, true, {})
end

--- jobstart wrapper
---@param cmd string|table
---@param on_success function|nil
---@param on_error function|nil
function M.ShellCmd(cmd, on_success, on_error)
	local ok = pcall(vim.fn.jobstart, cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_exit = function(_, code)
			if code == 0 then
				if on_success then
					on_success()
				end
			else
				if on_error then
					on_error()
				end
			end
		end,
	})
	if not ok then
		M.Notify("oz: something went wrong while executing cmd with jobstart().", "error", "Error")
		return
	end
end

--- input
---@param msg string
---@param def string|nil
---@return string|nil
function M.UserInput(msg, def)
	local ok, input = pcall(vim.fn.input, msg, def or "")
	if ok then
		return input
	end
end

function M.inactive_input(str, def)
	vim.api.nvim_set_hl(0, "ozInactivePrompt", { fg = "#757575" })
	vim.cmd("echohl ozInactivePrompt")
	local input = M.UserInput(str, def)
	vim.cmd("echohl None")
	return input
end

--- notify
---@param content string
---@param level string|nil
---@param title string|nil
function M.Notify(content, level, title)
	title = title or "Info"

	local level_map = {
		error = vim.log.levels.ERROR,
		warn = vim.log.levels.WARN,
		info = vim.log.levels.INFO,
		debug = vim.log.levels.DEBUG,
		trace = vim.log.levels.TRACE,
	}
	level = level_map[level] or vim.log.levels.INFO
	vim.notify(content, level, { title = title })
end

--- prompt
---@param str string
---@param choice string|nil
---@param default integer|nil
---@param hl string|nil
---@return string|nil
function M.prompt(str, choice, default, hl)
	local ok, res = pcall(vim.fn.confirm, str, choice, default, hl)
	if ok then
		return res
	end
end

-- big functions FIXME
function M.tbl_monitor()
	return require("oz.util.tbl_monitor")
end

function M.args_parser()
	return require("oz.util.parse_args")
end

--- string present in tbl
---@param str string
---@param string_table table
---@return boolean
function M.str_in_tbl(str, string_table)
	str = vim.trim(str)

	if str == "" then
		return false
	end

	for _, item in ipairs(string_table) do
		item = vim.trim(item)
		if string.find(str, item, 1, true) then
			return item
		end
	end

	return false
end

---remove item from tbl
---@param tbl table
---@param item any
function M.remove_from_tbl(tbl, item)
	for i, v in ipairs(tbl) do
		if v == item then
			table.remove(tbl, i)
			return
		end
	end
end

---join tbls
---@param tbl1 table
---@param tbl2 table
---@return table
function M.join_tables(tbl1, tbl2)
	for _, str in ipairs(tbl2) do
		table.insert(tbl1, str)
	end
	return tbl1
end

--- check if cmd exist
---@param name string
---@return boolean
function M.usercmd_exist(name)
	local commands = vim.api.nvim_get_commands({})
	return commands[name] ~= nil
end

function M.clear_qflist(title)
	local qf_list = vim.fn.getqflist({ title = 1 })
	if qf_list.title == title then
		vim.fn.setqflist({}, "r")
		vim.cmd("cclose")
	end
end

--- extract_flags
---@param cmd_str string
---@return table
function M.extract_flags(cmd_str)
	local flags = {}

	if not cmd_str or cmd_str == "" then
		return flags
	end

	for part in string.gmatch(cmd_str, "[^%s]+") do
		if string.sub(part, 1, 1) == "-" then
			table.insert(flags, part)
		end
	end

	return flags
end

--- get unique key
---@param tbl table
---@param key any
---@return any
function M.get_unique_key(tbl, key)
	local base_key = key
	local counter = 1
	while tbl[key] do
		key = base_key .. tostring(counter)
		counter = counter + 1
	end
	return key
end

return M
