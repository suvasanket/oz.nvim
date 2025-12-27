local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

local run_n_refresh = log_util.run_n_refresh
local cmd_upon_current_commit = log_util.cmd_upon_current_commit

function M.squash()
    cmd_upon_current_commit(function(hash)
        run_n_refresh("Git commit --squash " .. hash)
    end)
end

function M.fixup()
    cmd_upon_current_commit(function(hash)
        run_n_refresh("Git commit --fixup " .. hash)
    end)
end

function M.commit()
    cmd_upon_current_commit(function(hash)
        util.set_cmdline("Git commit| " .. hash)
    end)
end

function M.extend()
    cmd_upon_current_commit(function(hash)
        run_n_refresh(("Git commit -C %s -q"):format(hash))
    end)
end

function M.amend()
    cmd_upon_current_commit(function(hash)
        run_n_refresh(("Git commit -c %s -q"):format(hash))
    end)
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
		{
			title = "Commit Actions",
			items = {
				{ key = "s", cb = M.squash, desc = "Create commit with commit under cursor(--squash)" },
				{ key = "f", cb = M.fixup, desc = "Create commit with commit under cursor(--fixup)" },
				{ key = "c", cb = M.commit, desc = "Populate cmdline with Git commit followed by current hash" },
				{ key = "e", cb = M.extend, desc = "Create commit & reuse message from commit under cursor" },
				{ key = "a", cb = M.amend, desc = "Create commit & edit message from commit under cursor" },
			},
		},
	}

	util.Map("n", "c", function()
		require("oz.util.help_keymaps").show_menu("Commit Actions", options)
	end, { buffer = buf, desc = "Commit Actions", nowait = true })
end

return M
