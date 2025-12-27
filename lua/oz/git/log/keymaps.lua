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
end

return M