local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.merge_branch(flags)
	local branch_under_cursor = s_util.get_branch_under_cursor()
	local flag_str = ""
	if flags and #flags > 0 then
		flag_str = " " .. table.concat(flags, " ")
	end

	local input = util.inactive_input(":Git merge", flag_str .. " " .. (branch_under_cursor or ""))
	if input then
		s_util.run_n_refresh("Git merge" .. input)
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
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
				{ key = "m", cb = M.merge_branch, desc = "Merge" },
				{
					key = "e",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git merge " .. flags .. " ")
					end,
					desc = "Merge (edit cmd)",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "a",
					cb = function()
						s_util.run_n_refresh("Git merge --abort")
					end,
					desc = "Abort",
				},
				{
					key = "c",
					cb = function()
						s_util.run_n_refresh("Git merge --continue")
					end,
					desc = "Continue",
				},
				{
					key = "q",
					cb = function()
						s_util.run_n_refresh("Git merge --quit")
					end,
					desc = "Quit",
				},
			},
		},
	}
	util.Map("n", "m", function()
		require("oz.util.help_keymaps").show_menu("Merge Actions", m_opts)
	end, { buffer = buf, desc = "Merge Actions", nowait = true })
end

return M
