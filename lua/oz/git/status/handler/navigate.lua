local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.log()
	-- vim.cmd("close") -- Close status window before opening log
	require("oz.git.log").commit_log({ level = 1, from = "Git", win_type = "current" })
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

function M.setup_keymaps(buf, key_grp)
	vim.keymap.set("n", "<TAB>", function()
		local line = vim.api.nvim_win_get_cursor(0)[1]
		local status = require("oz.git.status")
		local item = status.state.line_map[line]
		local inline_diff = require("oz.git.status.inline_diff")

		if item then
			if item.type == "file" then
				if item.section_id == "untracked" then
					util.inactive_echo("No diff for untracked")
					return
				end
				inline_diff.toggle_inline_diff(
					buf,
					line,
					item.path,
					item.section_id,
					require("oz.git").state.root or util.GetProjectRoot(),
					item.path
				)
			elseif item.type == "header" then
				require("oz.git.status.util").toggle_section()
			end
		else
			local h = inline_diff.get_hunk_at_cursor(buf, line)
			if h then
				inline_diff.collapse_inline_diff(buf, h.file_line)
				vim.api.nvim_win_set_cursor(0, { h.file_line, 0 })
			end
		end
	end, { buffer = buf, desc = "Toggle inline diff or section" })

	local options = {
		{
			title = "Log",
			items = {
				{ key = "l", cb = M.log, desc = "goto commit logs" },
				{ key = "L", cb = M.log_context, desc = "goto commit logs for file/branch" },
			},
		},
		{
			title = "Goto",
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
				{
					key = "?",
					cb = function()
                        util.show_maps({
							group = key_grp,
							subtext = { "[<*> represents the key is actionable for the entry under cursor.]" },
							no_empty = true,
							on_open = function()
								vim.schedule(function()
									util.inactive_echo("press ctrl-f to search section")
								end)
							end,
						})
					end,
					desc = "Show all available keymaps",
				},
				{
					key = "g",
					cb = function()
						vim.cmd("normal! gg")
					end,
					desc = "goto top of the buffer",
				},
			},
		},
		{
			title = "File",
			items = {
				{ key = "I", cb = M.gitignore, desc = "Add file to .gitignore" },
			},
		},
	}

	vim.keymap.set("n", "g", function()
        util.show_menu("Goto", options)
	end, { buffer = buf, desc = "Goto Actions", nowait = true, silent = true })

	key_grp["Navigation"] = { "<TAB>" }
end

return M
