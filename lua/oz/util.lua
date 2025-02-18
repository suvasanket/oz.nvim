local M = {}

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

return M
