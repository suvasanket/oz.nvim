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

function M.diff(flags)
	local branches = g_util.get_branch()
	local stash = shell.shellout_tbl("git stash list --format=%gd")

	local all = util.join_tables(branches, stash)

	local flag_str = ""
	if flags and #flags > 0 then
		flag_str = " " .. table.concat(flags, " ")
	end

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

function M.diff_range()
	-- Prompt for range
	local range = util.UserInput("Diff range:")
	if range and range ~= "" then
		vim.cmd("DiffviewOpen " .. range)
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-f", name = "--function-context", type = "switch", desc = "Show function context" },
				{ key = "-w", name = "--ignore-all-space", type = "switch", desc = "Ignore whitespace" },
				{ key = "-b", name = "--ignore-space-change", type = "switch", desc = "Ignore space change" },
			},
		},
		{
			title = "Common",
			items = {
				{ key = "h", cb = M.file_history, desc = "Diff file history or stash" },
				{ key = "f", cb = M.file_changes, desc = "Diff file changes" },
			},
		},
	}

	if util.usercmd_exist("DiffviewOpen") or util.usercmd_exist("DiffviewFileHistory") then
		table.insert(options, {
			title = "Diffview",
			items = {
				{ key = "d", cb = M.diff, desc = "Diff" },
				{ key = "r", cb = M.diff_range, desc = "Diff range" },
				{
					key = "e",
					cb = function()
						util.set_cmdline("DiffviewOpen ")
					end,
					desc = "Populate cmd line with DiffviewOpen",
				},
				{
					key = "u",
					cb = function()
						vim.cmd("DiffviewOpen -uno")
					end,
					desc = "Diff all unstaged changes",
				},
				{
					key = "s",
					cb = function()
						vim.cmd("DiffviewOpen --staged")
					end,
					desc = "Diff all staged changes",
				},
			},
		})
	end

	util.Map("n", "d", function()
		require("oz.util.help_keymaps").show_menu("Diff Actions", options)
	end, { buffer = buf, desc = "Diff Actions", nowait = true })
end

return M
