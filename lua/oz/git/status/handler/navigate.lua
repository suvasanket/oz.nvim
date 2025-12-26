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
	local options = {
		{
			title = "Log",
			items = {
				{ key = "l", cb = M.log, desc = "goto commit logs" },
				{ key = "L", cb = M.log_context, desc = "goto commit logs for file/branch" },
			},
		},
		{
			title = "Section",
			items = {
				{
					key = "u",
					cb = function()
						s_util.jump_section("unstaged")
					end,
					desc = "Goto unstaged section",
				},
				{
					key = "s",
					cb = function()
						s_util.jump_section("staged")
					end,
					desc = "Goto staged section",
				},
				{
					key = "U",
					cb = function()
						s_util.jump_section("untracked")
					end,
					desc = "Goto untracked section",
				},
				{
					key = "z",
					cb = function()
						s_util.jump_section("stash")
					end,
					desc = "Goto stash section",
				},
				{
					key = "w",
					cb = function()
						s_util.jump_section("worktrees")
					end,
					desc = "Goto worktrees section",
				},
			},
		},
		{
			title = "File",
			items = {
				{ key = "I", cb = M.gitignore, desc = "Add file to .gitignore" },
				{
					key = "g",
					cb = function()
						vim.cmd("normal! gg")
					end,
					desc = "goto top of the buffer",
				},
			},
		},
	}

	util.Map("n", "g", function()
		require("oz.util.help_keymaps").show_menu("Goto", options)
	end, { buffer = buf, desc = "Goto Actions", nowait = true })
end

return M
