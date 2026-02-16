local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local grab_hashs = log.grab_hashs
local run_n_refresh = log_util.run_n_refresh
local clear_all_picked = log_util.clear_all_picked

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.handle_cherrypick(flags)
	local args = get_args(flags)
	local input
	if #grab_hashs > 0 then
		input = args .. " " .. table.concat(grab_hashs, " ")
		clear_all_picked()
	else
		local hash = get_selected_hash()
		util.exit_visual()
		if #hash == 1 then
			input = util.inactive_input(":Git cherry-pick", args .. " -x " .. hash[1])
		elseif #hash == 2 then
			input = util.inactive_input(":Git cherry-pick", args .. " -x " .. table.concat(hash, " "))
		elseif #hash > 2 then
			input = util.inactive_input(":Git cherry-pick", args .. " -x " .. hash[1] .. ".." .. hash[#hash])
		end
	end
	if input then
		run_n_refresh("Git cherry-pick" .. input)
	end
end

function M.abort()
    run_n_refresh("Git cherry-pick --abort")
end

function M.quit()
    run_n_refresh("Git cherry-pick --quit")
end

function M.continue()
    run_n_refresh("Git cherry-pick --continue")
end

function M.skip()
    run_n_refresh("Git cherry-pick --skip")
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-e", name = "--edit", type = "switch", desc = "Edit" },
				{ key = "-n", name = "--no-commit", type = "switch", desc = "No commit" },
				{ key = "-s", name = "--signoff", type = "switch", desc = "Signoff" },
				{ key = "-f", name = "--ff", type = "switch", desc = "Fast-forward" },
			},
		},
		{
			title = "Cherry Pick",
			items = {
				{ key = "p", cb = M.handle_cherrypick, desc = "Cherry-pick commit under cursor" },
				{ key = "a", cb = M.abort, desc = "Cherry-pick abort" },
				{ key = "q", cb = M.quit, desc = "Cherry-pick quit" },
				{ key = "l", cb = M.continue, desc = "Cherry-pick continue" },
				{ key = "k", cb = M.skip, desc = "Cherry-pick skip" },
			},
		},
	}

	util.Map("n", "p", function()
		require("oz.util.help_keymaps").show_menu("Cherry Pick Actions", options)
	end, { buffer = buf, desc = "Cherry Pick Actions", nowait = true })

	util.Map("x", "p", M.handle_cherrypick, { buffer = buf, desc = "Cherry-pick selection" })
end

return M
