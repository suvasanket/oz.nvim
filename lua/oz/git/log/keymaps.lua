local M = {}
local handle = require("oz.git.log.handler")

function M.keymaps_init(buf)
	local key_grp = {}

	handle.bisect.setup_keymaps(buf, key_grp)
	handle.branch.setup_keymaps(buf, key_grp)
	handle.cherry_pick.setup_keymaps(buf, key_grp)
	handle.commit.setup_keymaps(buf, key_grp)
	handle.diff.setup_keymaps(buf, key_grp)
	handle.fetch.setup_keymaps(buf, key_grp)
	handle.merge.setup_keymaps(buf, key_grp)
	handle.pull.setup_keymaps(buf, key_grp)
	handle.push.setup_keymaps(buf, key_grp)
	handle.rebase.setup_keymaps(buf, key_grp)
	handle.remote.setup_keymaps(buf, key_grp)
	handle.reset.setup_keymaps(buf, key_grp)
	handle.revert.setup_keymaps(buf, key_grp)
	handle.quick_action.setup_keymaps(buf, key_grp)
	handle.tag.setup_keymaps(buf, key_grp)
end

return M
