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

function M.revert(flags)
	local branches = g_util.get_branch()
	local args = get_args(flags)

	util.pick(branches, {
		title = "Revert",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git revert" .. args .. " " .. choice)
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
				{ key = "-s", name = "--signoff", type = "switch", desc = "Signoff" },
			},
		},
		{
			title = "Revert",
			items = {
				{ key = "v", cb = M.revert, desc = "Revert" },
				{ key = "V", cb = M.revert, desc = "Revert" },
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git revert " .. flags .. " ")
					end,
					desc = "Revert (edit cmd)",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "c",
					cb = function()
						s_util.run_n_refresh("Git revert --continue")
					end,
					desc = "Continue",
				},
				{
					key = "l",
					cb = function()
						s_util.run_n_refresh("Git revert --continue")
					end,
					desc = "Continue",
				},
				{
					key = "k",
					cb = function()
						s_util.run_n_refresh("Git revert --skip")
					end,
					desc = "Skip",
				},
				{
					key = "q",
					cb = function()
						s_util.run_n_refresh("Git revert --abort")
					end,
					desc = "Abort",
				},
                {
					key = "Q",
					cb = function()
						s_util.run_n_refresh("Git revert --quit")
					end,
					desc = "Quit",
				},
			},
		},
	}

	vim.keymap.set("n", "C", function()
		util.show_menu("Revert Actions", options)
	end, { buffer = buf, desc = "Revert Actions", nowait = true, silent = true })
end

return M
