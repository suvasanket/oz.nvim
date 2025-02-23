local M = {}

function M.inspect(var)
	return vim.inspect(var):gsub("%s+", " "):gsub("\n", "")
end

function M.GetProjectRoot(markers, path_or_bufnr)
	if markers then
		return vim.fs.root(path_or_bufnr or 0, markers) or nil
	end

	local patterns = { ".git", "Makefile", "package.json", "Cargo.toml", "go.mod", "pom.xml", "build.gradle" }
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
	return vim.keymap.set(mode, lhs, rhs, opts)
end

function M.echoprint(str, hl)
	if not hl then
		hl = "MoreMsg"
	end
	vim.api.nvim_echo({ { str, hl } }, true, {})
end

function M.ShellCmd(cmd, on_success, on_error)
	vim.fn.jobstart(cmd, {
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
end

function M.ShellOutput(cmd)
	local obj = vim.system({ "sh", "-c", cmd }, { text = true }):wait()
	local sout = obj.stdout:gsub("^%s+", ""):gsub("%s+$", "")
	return sout
end

function M.UserInput(msg, def)
	local ok, input = pcall(vim.fn.input, msg, def or "")
	if ok then
		return input
	end
end

function M.Notify(content, level, title)
	if not title then
		title = "Info"
	end
	if level == "error" then
		level = vim.log.levels.ERROR
	elseif level == "warn" then
		level = vim.log.levels.WARN
	end
	vim.notify(content, level, { title = title })
end

function M.prompt(str, opts, choice, hl)
	local ok, res = pcall(vim.fn.confirm, str, opts, choice, hl)
	if ok then
		return res
	end
end

function M.Show_buf_keymaps(args)
	local bufnr = vim.api.nvim_get_current_buf()
	local modes = { "n", "v", "i", "t" }

	local grouped_keymaps = {}
	for _, mode in ipairs(modes) do
		local maps = vim.api.nvim_buf_get_keymap(bufnr, mode)
		for _, map in ipairs(maps) do
			local key = map.lhs:gsub(" ", "<Space>")
			local desc = map.desc or map.rhs
			if desc then
				desc = desc:gsub("<Cmd>", ""):gsub("<CR>", "")
			else
				desc = "[No Info]"
			end
			if not grouped_keymaps[key] then
				grouped_keymaps[key] = {
					modes = {},
					desc = desc,
				}
			end
			table.insert(grouped_keymaps[key].modes, mode)
		end
	end

	local keymaps = {}
	for key, data in pairs(grouped_keymaps) do
		table.sort(data.modes)
		local modes_l = "[" .. table.concat(data.modes, ", ") .. "]"
		table.insert(keymaps, string.format(" %s  %s 󱦰 %s", modes_l, '"' .. key .. '"', data.desc))
	end

	table.sort(keymaps)

	-- Add subtext (footer)
	table.insert(keymaps, "")
	if args and args.subtext then
		for _, i in ipairs(args.subtext) do
			table.insert(keymaps, " " .. i)
		end
	end
	table.insert(keymaps, " press 'q' to close this window.")

	if #keymaps == 0 then
		return
	end

	local temp_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, keymaps)

	-- highlight
	vim.api.nvim_buf_call(temp_buf, function()
		vim.cmd("syntax clear")
		vim.cmd("highlight BoldKey gui=bold cterm=bold")
		vim.cmd('syntax match BoldKey /"\\(.*\\)"/ contains=NONE')
	end)

	-- floating window dimensions and position [ai]
	local fixed_width = 55
	local max_height = 15

	local wrapped_lines = {}
	for _, line in ipairs(keymaps) do
		for i = 1, #line, fixed_width do
			table.insert(wrapped_lines, line:sub(i, i + fixed_width - 1))
		end
	end
	local max_width = 0
	for _, line in ipairs(keymaps) do
		max_width = math.max(max_width, vim.fn.strwidth(line))
	end

	local height = math.min(#wrapped_lines, max_height)
	local width = (max_height > 100) and fixed_width or max_width + 2
	local row = vim.o.lines - height - 4
	local col = vim.o.columns - fixed_width - 2

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "single",
	}
	local temp_win = vim.api.nvim_open_win(temp_buf, true, win_opts)
	vim.api.nvim_buf_set_option(temp_buf, "modifiable", false)
	vim.api.nvim_buf_set_keymap(temp_buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
end

return M
