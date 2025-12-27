local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.fetch_cmd(flags)
	local args = get_args(flags)
	s_util.run_n_refresh("Git fetch" .. args)
end

function M.setup_keymaps(buf, key_grp)
	local fetch_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-p", name = "--prune", type = "switch", desc = "Prune" },
				{ key = "-t", name = "--tags", type = "switch", desc = "Tags" },
				{ key = "-f", name = "--force", type = "switch", desc = "Force" },
			},
		},
		{
			title = "Fetch",
			items = {
				{ key = "p", cb = M.fetch_cmd, desc = "Fetch upstream" },
				{ key = "u", cb = M.fetch_cmd, desc = "Fetch upstream" },
				{
					key = "a",
					cb = function(f)
						s_util.run_n_refresh("Git fetch --all" .. get_args(f))
					end,
					desc = "Fetch all",
				},
				{
					key = "e",
					cb = function(f)
						local args = get_args(f)
						util.set_cmdline("Git fetch" .. args .. " ")
					end,
					desc = "Fetch elsewhere",
				},
			},
		},
	}

	util.Map("n", "f", function()
		require("oz.util.help_keymaps").show_menu("Fetch Actions", fetch_opts)
	end, { buffer = buf, desc = "Fetch Actions", nowait = true })
end

return M
