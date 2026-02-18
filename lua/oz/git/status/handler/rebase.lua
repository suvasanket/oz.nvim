local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.rebase_branch(flags)
	local branch_under_cursor = s_util.get_branch_under_cursor()
	local flag_str = ""
	if flags and #flags > 0 then
		flag_str = " " .. table.concat(flags, " ")
	end
	-- Magit prompts for "Rebase <branch> on <upstream>" usually?
	-- Here we assume rebase current branch on selected.
	local input = util.inactive_input(":Git rebase", flag_str .. " " .. (branch_under_cursor or ""))
	if input then
		s_util.run_n_refresh("Git rebase" .. input)
	end
end

function M.rebase_interactive(flags)
	local branch_under_cursor = s_util.get_branch_under_cursor()
	local flag_str = ""
	if flags and #flags > 0 then
		flag_str = " " .. table.concat(flags, " ")
	end
	local input = util.inactive_input(":Git rebase -i", flag_str .. " " .. (branch_under_cursor or ""))
	if input then
		s_util.run_n_refresh("Git rebase -i" .. input)
	end
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
					key = "e",
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
					key = "s",
					cb = function()
						s_util.run_n_refresh("Git rebase --skip")
					end,
					desc = "Skip",
				},
				{
					key = "a",
					cb = function()
						s_util.run_n_refresh("Git rebase --abort")
					end,
					desc = "Abort",
				},
				{
					key = "t",
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
