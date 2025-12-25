local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.stage()
	local entries = s_util.get_file_under_cursor()
	local section = s_util.get_section_under_cursor()

	if #entries > 0 then
		util.ShellCmd({ "git", "add", unpack(entries) }, function()
			status.refresh_buf()
		end, function()
			util.Notify("Cannot stage selected.", "error", "oz_git")
		end)
	elseif section == "unstaged" then
		util.ShellCmd({ "git", "add", "-u" }, function()
			status.refresh_buf()
		end, function()
			util.Notify("Cannot stage selected.", "error", "oz_git")
		end)
	elseif section == "untracked" then
		util.set_cmdline(":Git add .")
	end
end

function M.unstage()
	local entries = s_util.get_file_under_cursor()
	local section = s_util.get_section_under_cursor()

	if #entries > 0 then
		util.ShellCmd({ "git", "restore", "--staged", unpack(entries) }, function()
			status.refresh_buf()
		end, function()
			util.Notify("Cannot unstage current entry.", "error", "oz_git")
		end)
	elseif section == "staged" then
		util.ShellCmd({ "git", "reset" }, function()
			status.refresh_buf()
		end, function()
			util.Notify("Cannot unstage current entry.", "error", "oz_git")
		end)
	end
end

function M.discard()
	local entries = s_util.get_file_under_cursor()
	if #entries > 0 then
		local confirm_ans = util.prompt("Discard all the changes?", "&Yes\n&No", 2)
		if confirm_ans == 1 then
			util.ShellCmd({ "git", "restore", unpack(entries) }, function()
				status.refresh_buf()
			end, function()
				util.Notify("Cannot discard currently selected.", "error", "oz_git")
			end)
		end
	end
end

function M.untrack()
	local entries = s_util.get_file_under_cursor()
	if #entries > 0 then
		util.ShellCmd({ "git", "rm", "--cached", unpack(entries) }, function()
			status.refresh_buf()
		end, function()
			util.Notify("currently selected can't be removed from tracking.", "error", "oz_git")
		end)
	end
end

function M.rename()
	local file = s_util.get_file_under_cursor(true)[1]
	local new_name = util.UserInput("New name: ", file)
	if new_name then
		s_util.run_n_refresh(string.format("Git mv %s %s", file, new_name))
	end
end

function M.setup_keymaps(buf, key_grp)
	util.Map(
		{ "n", "x" },
		"s",
		M.stage,
		{ buffer = buf, desc = "Stage entry under cursor or selected entries. <*>" }
	)
	-- unstage
	util.Map(
		{ "n", "x" },
		"u",
		M.unstage,
		{ buffer = buf, desc = "Unstage entry under cursor or selected entries. <*>" }
	)
	-- discard
	util.Map(
		{ "n", "x" },
		"X",
		M.discard,
		{ buffer = buf, desc = "Discard entry under cursor or selected entries. <*>" }
	)
	-- untrack
	util.Map({ "n", "x" }, "K", M.untrack, { buffer = buf, desc = "Untrack file or selected files. <*>" })
	util.Map("n", "R", M.rename, { buffer = buf, desc = "Rename the file under cursor. <*>" })
	key_grp["file"] = { "s", "u", "K", "X", "R" }
end

return M
