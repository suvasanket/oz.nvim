local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

function M.create()
	local hash = log_util.get_selected_hash()
	local tag_name = util.UserInput("Tag Name:")
	if tag_name and tag_name ~= "" then
		local cmd = "Git tag " .. tag_name
		if #hash > 0 then
			cmd = cmd .. " " .. hash[1]
		end
		log_util.run_n_refresh(cmd)
	end
end

function M.delete()
	local tags = util.shellout_tbl("git tag")
	util.pick(tags, {
		title = "Delete tag",
		on_select = function(choice)
			if choice then
				log_util.run_n_refresh("Git tag -d " .. choice)
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
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						local hash = log_util.get_selected_hash()
						local cmd = "Git tag " .. flags .. " "
						if #hash > 0 then
							cmd = cmd .. " " .. hash[1]
						end
						util.set_cmdline(cmd)
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
