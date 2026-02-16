local M = {}
local handle = require("oz.git.status.handler")

function M.keymaps_init(buf)
	local key_grp = {}

	-- Call setup_keymaps on each handler
	handle.quick_action.setup_keymaps(buf, key_grp)
	handle.file.setup_keymaps(buf, key_grp)
	handle.stash.setup_keymaps(buf, key_grp)
	handle.reset.setup_keymaps(buf, key_grp)
	handle.navigate.setup_keymaps(buf, key_grp)
	handle.commit.setup_keymaps(buf, key_grp)
	handle.diff.setup_keymaps(buf, key_grp)
	handle.merge.setup_keymaps(buf, key_grp)
	handle.rebase.setup_keymaps(buf, key_grp)
	handle.pick.setup_keymaps(buf, key_grp)
	handle.remote.setup_keymaps(buf, key_grp)
	handle.push.setup_keymaps(buf, key_grp)
	handle.pull.setup_keymaps(buf, key_grp)
	handle.fetch.setup_keymaps(buf, key_grp)
	handle.branch.setup_keymaps(buf, key_grp)
	handle.worktree.setup_keymaps(buf, key_grp)
	if require("oz.git.status").state.in_conflict then
		handle.conflict.setup_keymaps(buf)
        vim.notify_once("Conflict-Resolution mappings unlocked press 'x'")
	end
end

return M
