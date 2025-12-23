local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")

local refresh = status.refresh_buf

function M.stage()
	local entries = s_util.get_file_under_cursor()
	local current_line = vim.api.nvim_get_current_line()

	if #entries > 0 then
		util.ShellCmd({ "git", "add", unpack(entries) }, function()
			refresh()
		end, function()
			util.Notify("Cannot stage selected.", "error", "oz_git")
		end)
	elseif current_line:find("Changes not staged for commit:") then
		util.ShellCmd({ "git", "add", "-u" }, function()
			refresh()
		end, function()
			util.Notify("Cannot stage selected.", "error", "oz_git")
		end)
	elseif current_line:find("Untracked files:") then
		-- Consider using inactive_input or directly running if preferred
		vim.api.nvim_feedkeys(":Git add .", "n", false)
	end
end

function M.unstage()
	local entries = s_util.get_file_under_cursor()
	local current_line = vim.api.nvim_get_current_line()

	if #entries > 0 then
		util.ShellCmd({ "git", "restore", "--staged", unpack(entries) }, function()
			refresh()
		end, function()
			util.Notify("Cannot unstage current entry.", "error", "oz_git")
		end)
	elseif current_line:find("Changes to be committed:") then
		util.ShellCmd({ "git", "reset" }, function()
			refresh()
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
				refresh()
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
			refresh()
		end, function()
			util.Notify("currently selected can't be removed from tracking.", "error", "oz_git")
		end)
	end
end

return M
