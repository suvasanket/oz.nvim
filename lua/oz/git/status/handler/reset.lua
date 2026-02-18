local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.reset(args)
	-- args is a string like "--soft" or nil
	local files = s_util.get_file_under_cursor(true)
	local branch = s_util.get_branch_under_cursor()

	util.exit_visual()

	local cmd_args = args or ""

	if #files > 0 then
		-- Resetting files (unstage)
		s_util.run_n_refresh("Git reset " .. table.concat(files, " "))
		return
	elseif branch then
		-- Resetting branch/commit
		local input = util.inactive_input("Reset " .. (args or "mixed") .. " to:", branch)
		if input then
			s_util.run_n_refresh("Git reset " .. cmd_args .. " " .. input)
		end
		return
	end

	-- Default reset HEAD
	local input = util.inactive_input("Reset " .. (args or "mixed") .. " to:", "HEAD")
	if input then
		s_util.run_n_refresh("Git reset " .. cmd_args .. " " .. input)
	end
end

function M.undo_orig_head()
	s_util.run_n_refresh("Git reset ORIG_HEAD")
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Reset",
			items = {
				{
					key = "s",
					cb = function()
						M.reset("--soft")
					end,
					desc = "Soft (keep worktree & index)",
				},
				{
					key = "m",
					cb = function()
						M.reset("--mixed")
					end,
					desc = "Mixed (keep worktree)",
				},
				{
					key = "h",
					cb = function()
						M.reset("--hard")
					end,
					desc = "Hard (discard all)",
				},
				{
					key = "k",
					cb = function()
						M.reset("--keep")
					end,
					desc = "Keep (safe)",
				},
			},
		},
		{
			title = "Utilities",
			items = {
				{ key = "p", cb = M.undo_orig_head, desc = "Reset to ORIG_HEAD" },
				{
					key = "f",
					cb = function()
						M.reset(nil)
					end,
					desc = "Reset file/HEAD (Mixed)",
				},
			},
		},
	}
	vim.keymap.set("n", "U", function()
		util.show_menu("Reset Actions", options)
	end, { buffer = buf, desc = "Reset Actions", nowait = true, silent = true })

	vim.keymap.set("x", "U", M.reset, { buffer = buf, desc = "Reset selection", silent = true })
end

return M
