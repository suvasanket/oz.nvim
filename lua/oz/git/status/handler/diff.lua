local M = {}

local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local git = require("oz.git")
local shell = require("oz.util.shell")

function M.file_history()
	local cur_file = s_util.get_file_under_cursor()
	local stash = s_util.get_stash_under_cursor()
	if #cur_file > 0 then
		if util.usercmd_exist("DiffviewFileHistory") then
			vim.cmd("DiffviewFileHistory " .. cur_file[1])
		else
			vim.cmd(("Git difftool -y HEAD -- %s"):format(cur_file[1]))
			vim.fn.timer_start(700, function()
				git.cleanup_git_jobs({ cmd = "difftool" })
			end)
		end
	elseif #stash > 0 then
		if util.usercmd_exist("DiffviewFileHistory") then
			vim.cmd(("DiffviewFileHistory -g --range=stash@{%s}"):format(tostring(stash.index)))
		else
			util.Notify("following operation require diffview.nvim", "error", "oz_git")
		end
	end
end

function M.file_changes()
	local cur_file = s_util.get_file_under_cursor()
	if #cur_file > 0 then
		if util.usercmd_exist("DiffviewOpen") then
			vim.cmd("DiffviewOpen --selected-file=" .. cur_file[1])
			vim.schedule(function()
				vim.cmd("DiffviewToggleFiles")
			end)
		else
			vim.cmd(("Git difftool -y HEAD -- %s"):format(cur_file[1]))
			vim.fn.timer_start(700, function()
				git.cleanup_git_jobs({ cmd = "difftool" })
			end)
		end
	end
end

function M.diff()
	local branches = g_util.get_branch()
	local stash = shell.shellout_tbl("git stash list --format=%gd")

	local all = util.join_tables(branches, stash)

	vim.ui.select(all, {
		prompt = "lhs..",
	}, function(lhs)
		if not lhs then
			return
		end
		local rhs_options = vim.tbl_filter(function(item)
			return item ~= lhs
		end, all)

		vim.ui.select(rhs_options, {
			prompt = "..rhs",
		}, function(rhs)
			if not rhs then
				return
			end
			vim.cmd(string.format("DiffviewOpen %s..%s", lhs, rhs))
		end)
	end)
end

return M
