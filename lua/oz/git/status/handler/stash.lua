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
	util.Map("n", "za", M.apply, { buffer = buf, desc = "Apply stash under cursor. <*>" })
	util.Map("n", "zp", M.pop, { buffer = buf, desc = "Pop stash under cursor. <*>" })
	util.Map("n", "zd", M.drop, { buffer = buf, desc = "Drop stash under cursor. <*>" })
	util.Map("n", "z<space>", function()
		util.set_cmdline("Git stash ")
	end, { silent = false, buffer = buf, desc = "Populate cmdline with :Git stash." })
	util.Map("n", "zz", M.save, { buffer = buf, desc = "Stash save optionally add a message." })
	map_help_key("z", "stash")
	key_grp["stash[z]"] = { "zz", "za", "zp", "zd", "z<Space>", "z" }
end

return M
