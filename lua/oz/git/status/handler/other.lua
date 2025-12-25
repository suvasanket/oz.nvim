local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

-- stash
function M.stash_apply()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		s_util.run_n_refresh("G stash apply -q " .. stash)
	end
end

function M.stash_pop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		s_util.run_n_refresh("G stash pop -q " .. stash)
	end
end

function M.stash_drop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		s_util.run_n_refresh("G stash drop -q " .. stash)
	end
end

-- goto
function M.goto_log()
	vim.cmd("close") -- Close status window before opening log
	require("oz.git.log").commit_log({ level = 1, from = "Git" })
end

function M.goto_log_context()
	local branch = s_util.get_branch_under_cursor()
	local file = s_util.get_file_under_cursor(true)
	vim.cmd("close")
	if branch then
		require("oz.git.log").commit_log({ level = 1, from = "Git" }, { branch })
	elseif #file > 0 then
		--FIXME file log not working
		require("oz.git.log").commit_log({ level = 1, from = "Git" }, { "--", unpack(file) })
	else
		require("oz.git.log").commit_log({ level = 1, from = "Git" })
	end
end

function M.goto_gitignore()
	local path = s_util.get_file_under_cursor(true)
	if #path > 0 then
		require("oz.git.status.add_to_ignore").add_to_gitignore(path)
	end
end

-- reset
function M.reset(arg)
	local files = s_util.get_file_under_cursor(true)
	local branch = s_util.get_branch_under_cursor()
	local args = arg .. " HEAD~1"
	if #files > 0 then
		if arg then
			args = ("%s %s"):format(arg, table.concat(files, " "))
		else
			args = table.concat(files, " ")
		end
	elseif branch then
		if arg then
			args = ("%s %s"):format(arg, branch)
		else
			args = branch
		end
	end
	util.set_cmdline(("Git reset %s"):format(args or arg))
end

function M.undo_orig_head()
	s_util.run_n_refresh("Git reset ORIG_HEAD")
end

return M
