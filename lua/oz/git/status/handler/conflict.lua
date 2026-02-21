local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")

function M.list_conflicts()
	local root = g_util.get_project_root()
	local ok, out = util.run_command({ "git", "diff", "--name-only", "--diff-filter=U" }, root)

	if not ok or #out == 0 then
		util.Notify("No conflicted files found.", "warn", "oz_git")
		return
	end

	vim.ui.select(out, { prompt = "Select Conflicted File:" }, function(choice)
		if choice then
			vim.cmd("botright split " .. choice)
		end
	end)
end

function M.conflict_diffview()
	if util.usercmd_exist("DiffviewOpen") then
		vim.cmd("DiffviewOpen")
	else
		util.Notify("DiffviewOpen command not found.", "error", "oz_git")
	end
end

function M.conflict_three_way()
	-- Close status window first as we are opening a tab
	vim.cmd("close")
	require("oz.git.diff").resolve_three_way()
end

function M.setup_keymaps(buf)
	local x_opts = {
		{
			title = "Resolve",
			items = {
				{ key = "o", cb = M.conflict_three_way, desc = "Start 3-way merge resolution" },
				{ key = "l", cb = M.list_conflicts, desc = "List conflicted files" },
			},
		},
	}

	if util.usercmd_exist("DiffviewOpen") then
		table.insert(
			x_opts[1].items,
			{ key = "p", cb = M.conflict_diffview, desc = "Open Diffview for conflict resolution" }
		)
	end

	vim.keymap.set("n", "x", function()
		util.show_menu("Conflict Resolution", x_opts)
	end, { buffer = buf, desc = "Conflict Resolution", nowait = true, silent = true })
end

return M
