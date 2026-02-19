local M = {}

local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local shell = require("oz.util.shell")

-- Native Actions --
function M.file_history()
	local cur_file = s_util.get_file_under_cursor()
	local stash = s_util.get_stash_under_cursor()
	if #cur_file > 0 then
		vim.cmd("Git log -p -- " .. cur_file[1])
	elseif #stash > 0 then
		vim.cmd("Git show " .. tostring(stash.index))
	end
end

function M.file_changes()
	local cur_file = s_util.get_file_under_cursor()
	if #cur_file > 0 then
		vim.cmd("Git diff HEAD -- " .. cur_file[1])
	end
end

function M.diff(flags)
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
			local cmd = string.format("Git diff %s..%s", lhs, rhs)
			if flags and #flags > 0 then
				cmd = cmd .. " " .. table.concat(flags, " ")
			end
			vim.cmd(cmd)
		end)
	end)
end

function M.diff_range()
	local range = util.UserInput("Diff range:")
	if range and range ~= "" then
		vim.cmd("Git diff " .. range)
	end
end

function M.diff_unstaged()
	vim.cmd("Git diff")
end

function M.diff_staged()
	vim.cmd("Git diff --cached")
end

-- Diffview Actions --
function M.dv_file_history()
	local cur_file = s_util.get_file_under_cursor()
	local stash = s_util.get_stash_under_cursor()
	if #cur_file > 0 then
		vim.cmd("DiffviewFileHistory " .. cur_file[1])
	elseif #stash > 0 then
		vim.cmd(("DiffviewFileHistory -g --range=stash@{%s}"):format(tostring(stash.index)))
	end
end

function M.dv_file_changes()
	local cur_file = s_util.get_file_under_cursor()
	if #cur_file > 0 then
		vim.cmd("DiffviewOpen --selected-file=" .. cur_file[1])
		vim.schedule(function()
			vim.cmd("DiffviewToggleFiles")
		end)
	end
end

function M.dv_diff()
	local branches = g_util.get_branch()
	local stash = shell.shellout_tbl("git stash list --format=%gd")
	local all = util.join_tables(branches, stash)

	vim.ui.select(all, { prompt = "lhs.." }, function(lhs)
		if not lhs then
			return
		end
		local rhs_options = vim.tbl_filter(function(item)
			return item ~= lhs
		end, all)
		vim.ui.select(rhs_options, { prompt = "..rhs" }, function(rhs)
			if rhs then
				vim.cmd(string.format("DiffviewOpen %s..%s", lhs, rhs))
			end
		end)
	end)
end

function M.dv_diff_range()
	local range = util.UserInput("Diff range:")
	if range and range ~= "" then
		vim.cmd("DiffviewOpen " .. range)
	end
end

function M.setup_keymaps(buf, key_grp)
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
			title = "Native Diff",
			items = {
				{ key = "h", cb = M.file_history, desc = "File History / Stash Show" },
				{ key = "d", cb = M.file_changes, desc = "File Changes (vs HEAD)" },
				{ key = "j", cb = M.diff, desc = "Diff LHS..RHS" },
				{ key = "r", cb = M.diff_range, desc = "Diff Range" },
				{ key = "u", cb = M.diff_unstaged, desc = "Diff Unstaged" },
				{ key = "s", cb = M.diff_staged, desc = "Diff Staged" },
			},
		},
	}

	if util.usercmd_exist("DiffviewOpen") or util.usercmd_exist("DiffviewFileHistory") then
		table.insert(options, {
			title = "Diffview",
			items = {
				{ key = "H", cb = M.dv_file_history, desc = "File History" },
				{ key = "D", cb = M.dv_file_changes, desc = "File Changes" },
				{ key = "J", cb = M.dv_diff, desc = "Diff LHS..RHS" },
				{ key = "R", cb = M.dv_diff_range, desc = "Diff Range" },
				{
					key = "U",
					cb = function()
						vim.cmd("DiffviewOpen -uno")
					end,
					desc = "Diff Unstaged",
				},
				{
					key = "S",
					cb = function()
						vim.cmd("DiffviewOpen --staged")
					end,
					desc = "Diff Staged",
				},
				{
					key = " ",
					cb = function()
						util.set_cmdline("DiffviewOpen ")
					end,
					desc = "DiffviewOpen (cmdline)",
				},
			},
		})
	end

	vim.keymap.set("n", "d", function()
		util.show_menu("Diff Actions", options)
	end, { buffer = buf, desc = "Diff Actions", nowait = true, silent = true })
end

return M
