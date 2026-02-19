local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local run_n_refresh = log_util.run_n_refresh

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.interactive(flags)
	local args = get_args(flags)
	local current_hash = get_selected_hash()
	if #current_hash > 0 then
		run_n_refresh("Git rebase" .. args .. " -i " .. current_hash[1] .. "^")
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

function M.autosquash(flags)
	local args = get_args(flags)
	local hash = get_selected_hash()
	if #hash > 0 then
		run_n_refresh("Git rebase" .. args .. " -i --autosquash " .. hash[1] .. "^")
	end
end

function M.edit_todo()
    run_n_refresh("Git rebase --edit-todo")
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-a", name = "--autostash", type = "switch", desc = "Autostash" },
				{ key = "-k", name = "--keep-empty", type = "switch", desc = "Keep empty" },
				{ key = "-n", name = "--no-verify", type = "switch", desc = "No verify" },
			},
		},
		{
			title = "Rebase Actions",
			items = {
				{ key = "i", cb = M.interactive, desc = "Start interactive rebase including commit under cursor" },
				{ key = "r", cb = M.pick, desc = "Rebase with commit under cursor" },
				{ key = "l", cb = M.continue, desc = "Rebase continue" },
				{ key = "q", cb = M.abort, desc = "Rebase abort" },
				{ key = "Q", cb = M.quit, desc = "Rebase quit" },
				{ key = "k", cb = M.skip, desc = "Rebase skip" },
				{ key = "o", cb = M.autosquash, desc = "Start interactive rebase with commit under cursor(--autosquash)" },
				{ key = "e", cb = M.edit_todo, desc = "Rebase edit todo" },
			},
		},
	}

	vim.keymap.set("n", "r", function()
		util.show_menu("Rebase Actions", options)
	end, { buffer = buf, desc = "Rebase Actions", nowait = true, silent = true })
end

return M
