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

function M.paste_picked(flags)
	local log_mod = require("oz.git.log")
	local grab_hashs = log_mod.grab_hashs
	local log_util = require("oz.git.log.util")
	local clear_all_picked = log_util.clear_all_picked

	if #grab_hashs == 0 then
		util.Notify("No commits picked to paste.", "warn", "oz_git")
		return
	end

	local args = get_args(flags)
	local input = args .. " " .. table.concat(grab_hashs, " ")
	clear_all_picked()
	s_util.run_n_refresh("Git cherry-pick" .. input)
end

function M.setup_keymaps(buf, key_grp)
	local log_mod = require("oz.git.log")
	local picked_count = #log_mod.grab_hashs
	local paste_desc = picked_count > 0 and string.format("Paste/Apply %d picked commits", picked_count)
		or "Paste/Apply picked commits (none)"

	local options = {
		{
			title = "Cherry-pick",
			items = {
				{ key = "Y", cb = M.cherry_pick, desc = "Cherry-pick branch/ref..." },
				{ key = "P", cb = M.paste_picked, desc = paste_desc },
				{
					key = "x",
					cb = function()
						require("oz.git.log.util").clear_all_picked()
						util.Notify("Cleared all picked commits.", "info", "oz_git")
					end,
					desc = "Clear picked commits",
				},
			},
		},
		{
			title = "Actions",
			items = {
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
	}

	vim.keymap.set("n", "Y", function()
		util.show_menu("Cherry-pick Actions", options)
	end, { buffer = buf, desc = "Cherry-pick Actions", nowait = true, silent = true })
end

return M
