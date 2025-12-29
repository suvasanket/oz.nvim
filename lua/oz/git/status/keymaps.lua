local M = {}
local util = require("oz.util")
local show_map = require("oz.util.help_keymaps")
local handle = require("oz.git.status.handler")

function M.keymaps_init(buf)
	local key_grp = {}

	-- Helper to map specific help keys
	local function map_help_key(key, title)
		util.Map({ "n", "x" }, key, function()
			show_map.show_maps({ key = key, title = title, float = true })
		end, { buffer = buf })
	end

	-- Call setup_keymaps on each handler
	handle.quick_action.setup_keymaps(buf, key_grp)
	handle.file.setup_keymaps(buf, key_grp)
	handle.stash.setup_keymaps(buf, key_grp, map_help_key)
	handle.reset.setup_keymaps(buf, key_grp, map_help_key)
	handle.navigate.setup_keymaps(buf, key_grp, map_help_key)
	handle.commit.setup_keymaps(buf, key_grp, map_help_key)
	handle.diff.setup_keymaps(buf, key_grp, map_help_key)
	handle.merge.setup_keymaps(buf, key_grp, map_help_key)
	handle.rebase.setup_keymaps(buf, key_grp, map_help_key)
	handle.pick.setup_keymaps(buf, key_grp)
	handle.remote.setup_keymaps(buf, key_grp, map_help_key)
	handle.push.setup_keymaps(buf, key_grp)
	handle.pull.setup_keymaps(buf, key_grp)
	handle.fetch.setup_keymaps(buf, key_grp)
	handle.branch.setup_keymaps(buf, key_grp, map_help_key)
	handle.worktree.setup_keymaps(buf, key_grp, map_help_key)
	if require("oz.git.status").state.in_conflict then
		handle.conflict.setup_keymaps(buf)
        vim.notify_once("Conflict-Resolution mappings unlocked press 'x'")
	end
end

return M
