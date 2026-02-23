local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")

function M.rebase_branch(flags)
	local branches = g_util.get_branch()
	local flag_str = (flags and #flags > 0) and (" " .. table.concat(flags, " ")) or ""

	util.pick(branches, {
		title = "Rebase on",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git rebase" .. flag_str .. " " .. choice)
			end
		end,
	})
end

function M.rebase_interactive(flags)
	local branches = g_util.get_branch()
	local flag_str = (flags and #flags > 0) and (" " .. table.concat(flags, " ")) or ""

	util.pick(branches, {
		title = "Interactive Rebase on",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git rebase -i" .. flag_str .. " " .. choice)
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	local r_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-k", name = "--keep-base", type = "switch", desc = "Keep base" },
				{ key = "-a", name = "--autosquash", type = "switch", desc = "Autosquash" },
				{ key = "-S", name = "--autostash", type = "switch", desc = "Autostash" },
				{ key = "-i", name = "--interactive", type = "switch", desc = "Interactive" },
				{ key = "-p", name = "--preserve-merges", type = "switch", desc = "Preserve merges" }, -- Deprecated in newer git but still useful
			},
		},
		{
			title = "Rebase",
			items = {
				{ key = "r", cb = M.rebase_branch, desc = "Rebase on..." },
				{ key = "i", cb = M.rebase_interactive, desc = "Interactive" },
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git rebase " .. flags .. " ")
					end,
					desc = "Rebase (edit cmd)",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "c",
					cb = function()
						s_util.run_n_refresh("Git rebase --continue")
					end,
					desc = "Continue",
				},
				{
					key = "l",
					cb = function()
						s_util.run_n_refresh("Git rebase --continue")
					end,
					desc = "Continue",
				},
				{
					key = "k",
					cb = function()
						s_util.run_n_refresh("Git rebase --skip")
					end,
					desc = "Skip",
				},
				{
					key = "q",
					cb = function()
						s_util.run_n_refresh("Git rebase --abort")
					end,
					desc = "Abort",
				},
				{
					key = "Q",
					cb = function()
						s_util.run_n_refresh("Git rebase --quit")
					end,
					desc = "Quit",
				},
				{
					key = "e",
					cb = function()
						s_util.run_n_refresh("Git rebase --edit-todo")
					end,
					desc = "Edit todo",
				},
			},
		},
	}
	vim.keymap.set("n", "r", function()
		util.show_menu("Rebase Actions", r_opts)
	end, { buffer = buf, desc = "Rebase Actions", nowait = true, silent = true })
end

return M
