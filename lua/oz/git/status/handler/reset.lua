local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

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

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
		{
			title = "Basic",
			items = {
				{ key = "U", cb = M.reset, desc = "Reset file/branch" },
				{ key = "p", cb = M.undo_orig_head, desc = "Reset origin head" },
			},
		},
		{
			title = "Advanced",
			items = {
				{
					key = "s",
					cb = function()
						M.reset("--soft")
					end,
					desc = "Reset soft",
				},
				{
					key = "m",
					cb = function()
						M.reset("--mixed")
					end,
					desc = "Reset mixed",
				},
				{
					key = "h",
					cb = function()
						local confirm_ans = util.prompt("Do really really want to Git reset --hard ?", "&Yes\n&No", 2)
						if confirm_ans == 1 then
							M.reset("--hard")
						end
					end,
					desc = "Reset hard(danger)",
				},
			},
		},
	}
	util.Map("n", "U", function()
		require("oz.util.help_keymaps").show_menu("Reset Actions", options)
	end, { buffer = buf, desc = "Reset Actions", nowait = true })

	util.Map("x", "U", M.reset, { buffer = buf, desc = "Reset selection" })
end

return M
