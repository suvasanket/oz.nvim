local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.create()
	local tag_name = util.UserInput("Tag Name:")
	if tag_name and tag_name ~= "" then
		s_util.run_n_refresh("Git tag " .. tag_name)
	end
end

function M.delete()
	local tags = util.shellout_tbl("git tag")
	util.pick(tags, {
		title = "Delete tag",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git tag -d " .. choice)
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-a", name = "--annotate", type = "switch", desc = "Annotate" },
				{ key = "-f", name = "--force", type = "switch", desc = "Force" },
				{ key = "-s", name = "--sign", type = "switch", desc = "Sign" },
			},
		},
		{
			title = "Tag",
			items = {
				{ key = "t", cb = M.create, desc = "Create tag" },
				{ key = "d", cb = M.delete, desc = "Delete tag" },
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git tag " .. flags .. " ")
					end,
					desc = "Tag (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "t", function()
		util.show_menu("Tag Actions", options)
	end, { buffer = buf, desc = "Tag Actions", nowait = true, silent = true })
end

return M
