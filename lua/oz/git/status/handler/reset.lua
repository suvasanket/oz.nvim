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
	util.Map({ "n", "x" }, "UU", M.reset, { buffer = buf, desc = "Reset file/branch. <*>" })
	util.Map("n", "Up", M.undo_orig_head, { buffer = buf, desc = "Reset origin head." })
	util.Map("n", "Us", function()
		M.reset("--soft")
	end, { buffer = buf, desc = "Reset soft." })
	util.Map("n", "Um", function()
		M.reset("--mixed")
	end, { buffer = buf, desc = "Reset mixed." })
	util.Map("n", "Uh", function()
		local confirm_ans = util.prompt("Do really really want to Git reset --hard ?", "&Yes\n&No", 2)
		if confirm_ans == 1 then
			M.reset("--hard")
		end
	end, { buffer = buf, desc = "Reset hard(danger)." })
	map_help_key("U", "reset")
	key_grp["reset[U]"] = { "UU", "Up", "Uu", "Us", "Ux", "Uh", "Um" }
end

return M
