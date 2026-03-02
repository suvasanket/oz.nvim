local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

function M.merge_commit(flags)
	local hash = log_util.get_selected_hash()
	local flag_str = (flags and #flags > 0) and (" " .. table.concat(flags, " ")) or ""

	if #hash > 0 then
		log_util.run_n_refresh("Git merge" .. flag_str .. " " .. hash[1])
	else
		util.Notify("No commit selected to merge", "warn", "oz_git")
	end
end

function M.setup_keymaps(buf, key_grp)
	-- Merge mappings
	local m_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-f", name = "--ff-only", type = "switch", desc = "Fast-forward only" },
				{ key = "-n", name = "--no-ff", type = "switch", desc = "No fast-forward" },
				{ key = "-s", name = "--squash", type = "switch", desc = "Squash" },
				{ key = "-c", name = "--no-commit", type = "switch", desc = "No commit" },
			},
		},
		{
			title = "Merge",
			items = {
				{ key = "m", cb = M.merge_commit, desc = "Merge commit" },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "q",
					cb = function()
						log_util.run_n_refresh("Git merge --abort")
					end,
					desc = "Abort",
				},
				{
					key = "c",
					cb = function()
						log_util.run_n_refresh("Git merge --continue")
					end,
					desc = "Continue",
				},
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						local hash = log_util.get_selected_hash()
						local cmd = "Git merge " .. flags .. " "
						if #hash > 0 then
							cmd = cmd .. hash[1]
						end
						util.set_cmdline(cmd)
					end,
					desc = "Merge (edit cmd)",
				},
			},
		},
	}
	vim.keymap.set("n", "m", function()
		util.show_menu("Merge Actions", m_opts)
	end, { buffer = buf, desc = "Merge Actions", nowait = true, silent = true })
end

return M
