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
	local options = {
		{
			title = "Rebase Actions",
			items = {
				{ key = "i", cb = M.interactive, desc = "Start interactive rebase including commit under cursor" },
				{ key = "r", cb = M.pick, desc = "Rebase with commit under cursor" },
				{ key = "l", cb = M.continue, desc = "Rebase continue" },
				{ key = "a", cb = M.abort, desc = "Rebase abort" },
				{ key = "q", cb = M.quit, desc = "Rebase quit" },
				{ key = "k", cb = M.skip, desc = "Rebase skip" },
				{ key = "o", cb = M.autosquash, desc = "Start interactive rebase with commit under cursor(--autosquash)" },
				{ key = "e", cb = M.edit_todo, desc = "Rebase edit todo" },
			},
		},
	}

	util.Map("n", "r", function()
		require("oz.util.help_keymaps").show_menu("Rebase Actions", options)
	end, { buffer = buf, desc = "Rebase Actions", nowait = true })
end

return M
