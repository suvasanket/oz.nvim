local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

local run_n_refresh = log_util.run_n_refresh
local cmd_upon_current_commit = log_util.cmd_upon_current_commit

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.squash(flags)
	local args = get_args(flags)
	cmd_upon_current_commit(function(hash)
		run_n_refresh("Git commit" .. args .. " --squash " .. hash)
	end)
end

function M.fixup(flags)
	local args = get_args(flags)
	cmd_upon_current_commit(function(hash)
		run_n_refresh("Git commit" .. args .. " --fixup " .. hash)
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

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-e", name = "--edit", type = "switch", desc = "Edit" },
				{ key = "-n", name = "--no-verify", type = "switch", desc = "No verify" },
			},
		},
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

	vim.keymap.set("n", "c", function()
		util.show_menu("Commit Actions", options)
	end, { buffer = buf, desc = "Commit Actions", nowait = true, silent = true })
end

return M
