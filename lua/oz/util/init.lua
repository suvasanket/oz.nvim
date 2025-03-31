local M = {}

function M.tbl_insert(tbl, item)
	if not vim.tbl_contains(tbl, item) then
		table.insert(tbl, item)
	end
end

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

function M.Map(mode, lhs, rhs, opts)
	if not lhs then
		return
	end
	-- return vim.schedule_wrap(function()
	-- end)()
	vim.keymap.set(mode, lhs, rhs, opts)
end

function M.echoprint(str, hl)
	if not hl then
		hl = "MoreMsg"
	end
	vim.api.nvim_echo({ { str, hl } }, true, {})
end

function M.ShellCmd(cmd, on_success, on_error)
	local ok, id = pcall(vim.fn.jobstart, cmd, {
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

function M.ShellOutput(cmd)
	local obj = vim.system({ "sh", "-c", cmd }, { text = true }):wait()
	local sout = obj.stdout:gsub("^%s+", ""):gsub("%s+$", "")
	if vim.v.shell_error ~= 0 then
		return ""
	end
	return sout
end

function M.ShellOutputList(cmd)
	local sout = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		return {}
	else
		return sout
	end
end

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

function M.prompt(str, opts, choice, hl)
	local ok, res = pcall(vim.fn.confirm, str, opts, choice, hl)
	if ok then
		return res
	end
end

-- big functions
function M.Show_buf_keymaps(args)
	return require("oz.util.help_keymaps").init(args)
end

function M.tbl_monitor()
	return require("oz.util.tbl_monitor")
end

function M.str_in_tbl(str, string_table)
	str = vim.trim(str)
	for _, substring in ipairs(string_table) do
		substring = vim.trim(substring)

		local normalized_str = str:gsub("%s+", "")
		local normalized_substring = substring:gsub("%s+", "")

		if normalized_str == normalized_substring then
			return true
		end
	end
	return false
end

function M.remove_from_tbl(tbl, item)
	for i, v in ipairs(tbl) do
		if v == item then
			table.remove(tbl, i)
			return
		end
	end
end

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

return M
