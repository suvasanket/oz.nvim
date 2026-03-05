local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.fetch_cmd(flags)
	local args = get_args(flags)
	log_util.run_n_refresh("Git fetch" .. args)
end

function M.setup_keymaps(buf, key_grp)
	local fetch_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-p", name = "--prune", type = "switch", desc = "Prune" },
				{ key = "-t", name = "--tags", type = "switch", desc = "Tags" },
				{ key = "-f", name = "--force", type = "switch", desc = "Force" },
				{ key = "-q", name = "--quiet", type = "switch", desc = "Quiet" },
			},
		},
		{
			title = "Fetch",
			items = {
				{ key = "f", cb = M.fetch_cmd, desc = "Fetch upstream" },
				{
					key = "a",
					cb = function(f)
						log_util.run_n_refresh("Git fetch --all" .. get_args(f))
					end,
					desc = "Fetch all",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local args = get_args(f)
						util.set_cmdline("Git fetch" .. args .. " ")
					end,
					desc = "Fetch elsewhere",
				},
			},
		},
	}

	vim.keymap.set("n", "f", function()
		util.show_menu("Fetch Actions", fetch_opts)
	end, { buffer = buf, desc = "Fetch Actions", nowait = true, silent = true })
end

return M
