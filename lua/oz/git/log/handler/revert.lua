local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local grab_hashs = log.grab_hashs
local run_n_refresh = log_util.run_n_refresh
local clear_all_picked = log_util.clear_all_picked

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.handle_revert(flags)
	local args = get_args(flags)
	local str
	if #grab_hashs > 0 then
		str = table.concat(grab_hashs, " ")
		clear_all_picked()
	else
		local commits = get_selected_hash()
		util.exit_visual()
		if #commits == 1 then
			str = commits[1]
		elseif #commits == 2 then
			str = ("%s %s"):format(commits[1], commits[2])
		elseif #commits > 2 then
			str = ("%s..%s"):format(commits[1], commits[#commits])
		end
	end
	if str then
        run_n_refresh("Git! revert" .. args .. " " .. str)
	end
end

function M.edit()
	local hash = get_selected_hash()
	if #hash == 1 then
		run_n_refresh("Git revert --edit " .. hash[1])
	end
end

function M.continue()
	run_n_refresh("Git revert --continue")
end

function M.skip()
	run_n_refresh("Git revert --skip")
end

function M.quit()
	run_n_refresh("Git revert --quit")
end

function M.abort()
	run_n_refresh("Git revert --abort")
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-n", name = "--no-commit", type = "switch", desc = "No commit" },
				{ key = "-s", name = "--signoff", type = "switch", desc = "Signoff" },
			},
		},
		{
			title = "Revert",
			items = {
				{ key = "C", cb = M.handle_revert, desc = "Revert selection or current commit" },
				{ key = "w", cb = M.edit, desc = "Revert commit with edit" },
			},
		},
		{
			title = "Actions",
			items = {
				{ key = "l", cb = M.continue, desc = "Revert continue" },
				{ key = "k", cb = M.skip, desc = "Revert skip" },
				{ key = "Q", cb = M.quit, desc = "Revert quit" },
				{ key = "q", cb = M.abort, desc = "Revert abort" },
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git revert " .. flags .. " ")
					end,
					desc = "Revert (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set({ "n", "x" }, "C", function()
		util.show_menu("Revert Actions", options)
	end, { buffer = buf, desc = "Revert Actions", nowait = true, silent = true })
end

return M
