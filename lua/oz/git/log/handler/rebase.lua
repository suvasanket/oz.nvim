local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local run_n_refresh = log_util.run_n_refresh

function M.interactive()
    local current_hash = get_selected_hash()
    if #current_hash > 0 then
        run_n_refresh("Git rebase -i " .. current_hash[1] .. "^")
    end
end

function M.pick()
    local current_hash = get_selected_hash()
    if #current_hash == 1 then
        util.set_cmdline("Git rebase| " .. current_hash[1])
    end
end

function M.continue()
    run_n_refresh("Git rebase --continue")
end

function M.abort()
    run_n_refresh("Git rebase --abort")
end

function M.quit()
    run_n_refresh("Git rebase --quit")
end

function M.skip()
    run_n_refresh("Git rebase --skip")
end

function M.autosquash()
    local hash = get_selected_hash()
    if #hash > 0 then
        run_n_refresh("Git rebase -i --autosquash " .. hash[1] .. "^")
    end
end

function M.edit_todo()
    run_n_refresh("Git rebase --edit-todo")
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	util.Map("n", "ri", M.interactive, { buffer = buf, desc = "Start interactive rebase including commit under cursor. <*>" })
	util.Map("n", "rr", M.pick, { buffer = buf, desc = "Rebase with commit under cursor. <*>" })
	util.Map("n", "rl", M.continue, { buffer = buf, desc = "Rebase continue." })
	util.Map("n", "ra", M.abort, { buffer = buf, desc = "Rebase abort." })
	util.Map("n", "rq", M.quit, { buffer = buf, desc = "Rebase quit." })
	util.Map("n", "rk", M.skip, { buffer = buf, desc = "Rebase skip." })
	util.Map("n", "ro", M.autosquash, { buffer = buf, desc = "Start interactive rebase with commit under cursor(--autosquash). <*>" })
	util.Map("n", "re", M.edit_todo, { buffer = buf, desc = "Rebase edit todo." })
	map_help_key("r", "rebase")
	key_grp["rebase[r]"] = { "rr", "ri", "rl", "ra", "rq", "rk", "ro", "re" }
end

return M
