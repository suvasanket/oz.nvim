local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.log()
	vim.cmd("close") -- Close status window before opening log
	require("oz.git.log").commit_log({ level = 1, from = "Git" })
end

function M.log_context()
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

function M.gitignore()
	local path = s_util.get_file_under_cursor(true)
	if #path > 0 then
		require("oz.git.status.add_to_ignore").add_to_gitignore(path)
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	util.Map("n", "gl", M.log, { buffer = buf, desc = "goto commit logs." })
	util.Map("n", "gL", M.log_context, { buffer = buf, desc = "goto commit logs for file/branch. <*>" })

	util.Map("n", "gu", function()
		s_util.jump_section("unstaged")
	end, { buffer = buf, desc = "Goto unstaged section." })
	util.Map("n", "gs", function()
		s_util.jump_section("staged")
	end, { buffer = buf, desc = "Goto staged section." })
	util.Map("n", "gU", function()
		s_util.jump_section("untracked")
	end, { buffer = buf, desc = "Goto untracked section." })
	util.Map("n", "gz", function()
		s_util.jump_section("stash")
	end, { buffer = buf, desc = "Goto stash section." })
	util.Map("n", "gw", function()
		s_util.jump_section("worktrees")
	end, { buffer = buf, desc = "Goto worktrees section." })

	util.Map({ "n", "x" }, "gI", M.gitignore, { buffer = buf, desc = "Add file to .gitignore. <*>" })
	util.Map("n", "gg", "gg", { buffer = buf, desc = "goto top of the buffer." })
	map_help_key("g", "goto")
	key_grp["goto[g]"] = { "gI", "gw", "gu", "gs", "gU", "gz", "gl", "gL", "gg", "g?" }
end

return M
