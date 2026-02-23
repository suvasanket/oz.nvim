local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")

function M.merge_branch(flags)
	local branches = g_util.get_branch()
	local flag_str = (flags and #flags > 0) and (" " .. table.concat(flags, " ")) or ""

	util.pick(branches, {
		title = "Merge branch",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git merge" .. flag_str .. " " .. choice)
			end
		end,
	})
end

function M.squash_merge(flags)
	local branches = g_util.get_branch()
	local flag_str = (flags and #flags > 0) and (" " .. table.concat(flags, " ")) or ""

	util.pick(branches, {
		title = "Squash merge branch",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git merge --squash" .. flag_str .. " " .. choice)
			end
		end,
	})
end

function M.preview_merge()
	local branches = g_util.get_branch()
	util.pick(branches, {
		title = "Preview merge branch",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git merge --no-commit --no-ff " .. choice)
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	-- Merge mappings
	local m_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-f", name = "--ff-only", type = "switch", desc = "Fast-forward only" },
				{ key = "-n", name = "--no-ff", type = "switch", desc = "No fast-forward" },
				{ key = "-s", name = "--squash", type = "switch", desc = "Squash" },
				{ key = "-c", name = "--no-commit", type = "switch", desc = "No commit" },
			},
		},
		{
			title = "Merge",
			items = {
				{ key = "m", cb = M.merge_branch, desc = "Merge" },
				{ key = "s", cb = M.squash_merge, desc = "Squash merge" },
				{ key = "p", cb = M.preview_merge, desc = "Preview merge" },
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git merge " .. flags .. " ")
					end,
					desc = "Merge (edit cmd)",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "q",
					cb = function()
						s_util.run_n_refresh("Git merge --abort")
					end,
					desc = "Abort",
				},
				{
					key = "c",
					cb = function()
						s_util.run_n_refresh("Git merge --continue")
					end,
					desc = "Continue",
				},
				{
					key = "l",
					cb = function()
						s_util.run_n_refresh("Git merge --continue")
					end,
					desc = "Continue",
				},
				{
					key = "Q",
					cb = function()
						s_util.run_n_refresh("Git merge --quit")
					end,
					desc = "Quit",
				},
			},
		},
	}
	vim.keymap.set("n", "m", function()
		util.show_menu("Merge Actions", m_opts)
	end, { buffer = buf, desc = "Merge Actions", nowait = true, silent = true })
end

return M
