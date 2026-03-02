local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Bisect",
			items = {
				{
					key = "B",
					cb = function()
						s_util.run_n_refresh("Git! bisect start")
					end,
					desc = "Start",
				},
				{
					key = "g",
					cb = function()
						s_util.run_n_refresh("Git! bisect good")
					end,
					desc = "Good",
				},
				{
					key = "b",
					cb = function()
						s_util.run_n_refresh("Git! bisect bad")
					end,
					desc = "Bad",
				},
			},
		},
		{
			title = "Actions",
			items = {
                {
					key = "q",
					cb = function()
						s_util.run_n_refresh("Git! bisect reset")
					end,
					desc = "Quit (Reset)",
				},
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git! bisect " .. flags .. " ")
					end,
					desc = "Bisect (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "B", function()
		util.show_menu("Bisect Actions", options)
	end, { buffer = buf, desc = "Bisect Actions", nowait = true, silent = true })
end

return M
