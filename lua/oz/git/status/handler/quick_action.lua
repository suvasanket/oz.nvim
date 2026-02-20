local M = {}
local status = require("oz.git.status")
local s_util = require("oz.git.status.util")
local util = require("oz.util")

function M.quit()
	vim.api.nvim_echo({ { "" } }, false, {})
	if not pcall(vim.cmd.close) then
		pcall(vim.cmd.blast)
	end
end

function M.enter_key()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local item = status.state.line_map[cursor_line]

	if not item then
		return
	end

	-- 1. Header Toggle
	if item.type == "header" then
		s_util.toggle_section()
		return
	end

	-- 2. Worktree
	if item.type == "worktree" then
		local worktree = s_util.get_worktree_under_cursor()
		if worktree then
			local full_path = status.state.worktree_map[worktree.path]

			if full_path and vim.loop.fs_stat(full_path) then
				-- vim.cmd("split | edit " .. vim.fn.fnameescape(full_path))
                util.open_in_split(vim.fn.fnameescape(full_path))
			else
				util.Notify("Worktree doesn't exist(prunable).", "warn", "oz_git")
			end
		end
		return
	end

	-- 3. Branch
	if item.type == "branch_item" then
		local branch = s_util.get_branch_under_cursor()
		if branch then
			if branch == status.state.current_branch then
				vim.cmd.close()
				require("oz.git.log").commit_log({ level = 1, from = "Git" }, { branch })
			else
				s_util.run_n_refresh(string.format("Git switch %s --quiet", branch))
			end
		end
		return
	end

	-- 4. Stash
	if item.type == "stash" then
		local stash = s_util.get_stash_under_cursor()
		if stash.index then
			vim.cmd(string.format("Git stash show -p stash@{%d}", stash.index))
		end
		return
	end

	-- 5. Files
	if item.type == "file" then
		local files = s_util.get_file_under_cursor()
		if #files > 0 then
			local target = files[1]
			if vim.fn.filereadable(target) == 1 or vim.fn.isdirectory(target) == 1 then
				-- vim.cmd("split | edit " .. vim.fn.fnameescape(target)) -- WIP
				util.open_in_split(vim.fn.fnameescape(target))
			end
		end
		return
	end
end

function M.setup_keymaps(buf, key_grp)
	vim.keymap.set("n", "q", M.quit, { buffer = buf, desc = "Close git status buffer.", silent = true })
	-- vim.keymap.set("n", "<Tab>", function()
	-- 	s_util.jump_section(1)
	-- end, { buffer = buf, desc = "Jump to next section.", silent = true })
	-- vim.keymap.set("n", "<S-Tab>", function()
	-- 	s_util.jump_section(-1)
	-- end, { buffer = buf, desc = "Jump to previous section.", silent = true })
	vim.keymap.set("n", "<C-r>", status.refresh_buf, { buffer = buf, desc = "Refresh status buffer.", silent = true })
	vim.keymap.set("n", "-", function()
		util.set_cmdline("Git ")
	end, { silent = false, buffer = buf, desc = "Populate cmdline with :Git." })
	vim.keymap.set("n", "<cr>", M.enter_key, { buffer = buf, desc = "Open entry under cursor.", silent = true })
	vim.keymap.set("n", "I", "<cmd>Git reflog<cr>", { buffer = buf, desc = "Open reflog", silent = true })
	key_grp["Quick actions"] = { "-", "<Tab>", "<S-Tab>", "<CR>", "I", "<C-R>", "q" }
end

return M
