local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.apply()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		s_util.run_n_refresh("G stash apply -q " .. stash)
	end
end

function M.pop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		s_util.run_n_refresh("G stash pop -q " .. stash)
	end
end

function M.drop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		s_util.run_n_refresh("G stash drop -q " .. stash)
	end
end

function M.save()
	local input = util.inactive_input(":Git stash", " save ")
	if input then
		s_util.run_n_refresh("Git stash" .. input)
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
		{
			title = "Create",
			items = {
				{ key = "z", cb = M.save, desc = "Stash save optionally add a message" },
				{
					key = "<Space>",
					cb = function()
						util.set_cmdline("Git stash ")
					end,
					desc = "Populate cmdline with :Git stash",
				},
			},
		},
		{
			title = "Manage",
			items = {
				{ key = "a", cb = M.apply, desc = "Apply stash under cursor" },
				{ key = "p", cb = M.pop, desc = "Pop stash under cursor" },
				{ key = "d", cb = M.drop, desc = "Drop stash under cursor" },
			},
		},
	}

	util.Map("n", "z", function()
		require("oz.util.help_keymaps").show_menu("Stash Actions", options)
	end, { buffer = buf, desc = "Stash Actions", nowait = true })
end

return M
