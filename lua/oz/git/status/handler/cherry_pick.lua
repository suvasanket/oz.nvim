local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")

local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.cherry_pick(flags)
	local branches = g_util.get_branch()
	local args = get_args(flags)

	util.pick(branches, {
		title = "Cherry-pick",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git cherry-pick" .. args .. " " .. choice)
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-n", name = "--no-commit", type = "switch", desc = "No commit" },
				{ key = "-x", name = "-x", type = "switch", desc = "Append (cherry picked from...)" },
				{ key = "-s", name = "--signoff", type = "switch", desc = "Signoff" },
			},
		},
		{
			title = "Cherry-pick",
			items = {
				{ key = "A", cb = M.cherry_pick, desc = "Cherry-pick" },
				{ key = "a", cb = M.cherry_pick, desc = "Cherry-pick" },
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git cherry-pick " .. flags .. " ")
					end,
					desc = "Cherry-pick (edit cmd)",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "c",
					cb = function()
						s_util.run_n_refresh("Git cherry-pick --continue")
					end,
					desc = "Continue",
				},
				{
					key = "l",
					cb = function()
						s_util.run_n_refresh("Git cherry-pick --continue")
					end,
					desc = "Continue",
				},
				{
					key = "k",
					cb = function()
						s_util.run_n_refresh("Git cherry-pick --skip")
					end,
					desc = "Skip",
				},
				{
					key = "q",
					cb = function()
						s_util.run_n_refresh("Git cherry-pick --abort")
					end,
					desc = "Abort",
				},
                {
					key = "Q",
					cb = function()
						s_util.run_n_refresh("Git cherry-pick --quit")
					end,
					desc = "Quit",
				},
			},
		},
	}

	vim.keymap.set("n", "A", function()
		util.show_menu("Cherry-pick Actions", options)
	end, { buffer = buf, desc = "Cherry-pick Actions", nowait = true, silent = true })
end

return M
