local M = {}
local status = require("oz.git.status")
local s_util = require("oz.git.status.util")
local util = require("oz.util")

function M.quit()
	vim.api.nvim_echo({ { "" } }, false, {})
	vim.cmd("close")
end

function M.tab()
	if s_util.toggle_section() then
		return
	end
end

function M.enter_key()
	-- 1. Header Toggle
	local section_id = s_util.get_section_under_cursor()
	if section_id then
		s_util.toggle_section()
		return
	end

	-- 2. Worktree (Map Lookup)
	local worktree = s_util.get_worktree_under_cursor()
	if worktree then
		local full_path = status.state.worktree_map[worktree.path]

		if full_path and vim.loop.fs_stat(full_path) then
			vim.cmd("wincmd k | edit " .. vim.fn.fnameescape(full_path))
		else
			util.Notify("Worktree doesn't exist(prunable).", "warn", "oz_git")
		end
		return
	end

	-- branch
	local branch = s_util.get_branch_under_cursor()
	if branch then
		if branch == status.state.current_branch then
			vim.cmd.close()
			require("oz.git.log").commit_log({ level = 1, from = "Git" }, { branch })
		else
			s_util.run_n_refresh(string.format("Git switch %s --quiet", branch))
		end
		return
	end

	-- stash
	local stash = s_util.get_stash_under_cursor()
	if stash.index then
		vim.cmd(string.format("Git stash show -p stash@{%d}", stash.index))
		return
	end

	-- files
	local files = s_util.get_file_under_cursor()
	if #files > 0 then
		local target = files[1]
		if vim.fn.filereadable(target) == 1 or vim.fn.isdirectory(target) == 1 then
			vim.cmd("wincmd k | edit " .. vim.fn.fnameescape(target))
		end
		return
	end
end

return M
