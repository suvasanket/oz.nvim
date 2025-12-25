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
	util.Map("n", "cs", M.squash, { buffer = buf, desc = "Create commit with commit under cursor(--squash). <*>" })
	util.Map("n", "cf", M.fixup, { buffer = buf, desc = "Create commit with commit under cursor(--fixup). <*>" })
	util.Map("n", "cc", M.commit, { buffer = buf, desc = "Populate cmdline with Git commit followed by current hash. <*>" })
	util.Map("n", "ce", M.extend, { buffer = buf, desc = "Create commit & reuse message from commit under cursor. <*>" })
	util.Map("n", "ca", M.amend, { buffer = buf, desc = "Create commit & edit message from commit under cursor. <*>" })
	map_help_key("c", "commit")
	key_grp["commit[c]"] = { "cs", "cf", "cc", "ce", "ca" }
end

return M
