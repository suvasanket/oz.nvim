local M = {}
local handle = require("oz.git.log.handler")

function M.keymaps_init(buf)
	local key_grp = {}

	handle.cherry_pick.setup_keymaps(buf, key_grp)
	handle.commit.setup_keymaps(buf, key_grp)
	handle.diff.setup_keymaps(buf, key_grp)
	handle.rebase.setup_keymaps(buf, key_grp)
	handle.reset.setup_keymaps(buf, key_grp)
	handle.revert.setup_keymaps(buf, key_grp)
	handle.quick_action.setup_keymaps(buf, key_grp)
	handle.switch.setup_keymaps(buf, key_grp)
end

return M

