local M = {}
local util = require("oz.util")
local show_maps = require("oz.util.help_keymaps")
local handle = require("oz.git.log.handler")

function M.keymaps_init(buf)
	local key_grp = {}

	-- Helper to map specific help keys
	local function map_help_key(key, title)
		util.Map({ "n", "x" }, key, function()
			show_maps.show_maps({ key = key, title = title, float = true })
		end, { buffer = buf })
	end

    handle.cherry_pick.setup_keymaps(buf, key_grp, map_help_key)
    handle.commit.setup_keymaps(buf, key_grp, map_help_key)
    handle.diff.setup_keymaps(buf, key_grp, map_help_key)
    handle.rebase.setup_keymaps(buf, key_grp, map_help_key)
    handle.reset.setup_keymaps(buf, key_grp, map_help_key)
    handle.revert.setup_keymaps(buf, key_grp, map_help_key)
    handle.quick_action.setup_keymaps(buf, key_grp, map_help_key)

	-- help
	util.Map("n", "g?", function()
		show_maps.show_maps({
			group = key_grp,
			subtext = { "[<*> represents the key is actionable for the entry under cursor.]" },
			no_empty = true,
			on_open = function()
				vim.schedule(function()
					util.inactive_echo("press ctrl-f to search section")
				end)
			end,
		})
	end, { buffer = buf, desc = "Show all availble keymaps." })
end

return M