local M = {}
local util = require("oz.util")
local log = require("oz.git.log")

local get_selected_hash = log.get_selected_hash

function M.handle_reset(arg)
	local current_hash = get_selected_hash()
	if #current_hash > 0 then
		if not arg then
			util.set_cmdline(("Git reset| %s^"):format(current_hash[1]))
		else
			util.set_cmdline(("Git reset %s %s^"):format(arg, current_hash[1]))
		end
	end
end

function M.soft()
	M.handle_reset("--soft")
end

function M.mixed()
	M.handle_reset("--mixed")
end

function M.hard()
	M.handle_reset("--hard")
end

function M.tag()
	local ch = { "--hard", "--soft", "--mixed" }
	util.pick(ch, {
		title = "Pick reset mode",
		on_select = function(choice)
			if choice then
				local tags = util.shellout_tbl("git tag")
				util.pick(tags, {
					title = "Pick tag",
					on_select = function(tagc)
						if tagc then
							util.set_cmdline(("Git reset %s %s"):format(choice, tagc))
						end
					end,
				})
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Reset",
			items = {
				{ key = "U", cb = M.handle_reset, desc = "Reset commit" },
				{ key = "s", cb = M.soft, desc = "Reset commit(--soft)" },
				{ key = "m", cb = M.mixed, desc = "Reset commit(--mixed)" },
				{ key = "h", cb = M.hard, desc = "Reset commit(--hard)" },
				{ key = "t", cb = M.tag, desc = "Reset to tag" },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git reset " .. flags .. " ")
					end,
					desc = "Reset (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "U", function()
		util.show_menu("Reset Actions", options)
	end, { buffer = buf, desc = "Reset Actions", nowait = true, silent = true })
end

return M
