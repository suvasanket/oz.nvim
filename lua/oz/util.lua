local M = {}

function M.GetProjectRoot()
	local workspace = vim.lsp.buf.list_workspace_folders()
	local firstworkspace = workspace[1]
	if firstworkspace then
		if firstworkspace == vim.fn.expand("~"):gsub("/$", "") then
            return nil
		end
		return firstworkspace
	end
	return vim.fs.root(0, ".git") or nil
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

function M.TableContainsValue(tab, val)
	for index, value in ipairs(tab) do
		if value == val then
			return true
		end
	end

	return false
end

function M.Notify(content, level, title)
	if not title then
		title = "Info"
	end
	if level == "error" then
		level = vim.log.levels.ERROR
	end
	vim.notify(content, level, { title = title })
end

return M
