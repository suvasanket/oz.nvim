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

function M.save(flags)
    local args = ""
    if flags and #flags > 0 then
        args = " " .. table.concat(flags, " ")
    end
	local input = util.inactive_input(":Git stash save" .. args, " ")
	if input then
		s_util.run_n_refresh("Git stash save" .. args .. input)
	else
        -- If just flags and no message?
        if args ~= "" then
             s_util.run_n_refresh("Git stash save" .. args)
        end
    end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
        {
            title = "Switches",
            items = {
                { key = "-u", name = "--include-untracked", type = "switch", desc = "Include untracked" },
                { key = "-a", name = "--all", type = "switch", desc = "Include all (ignored)" },
                { key = "-k", name = "--keep-index", type = "switch", desc = "Keep index" },
            }
        },
		{
			title = "Stash",
			items = {
				{ key = "z", cb = M.save, desc = "Stash" },
				{
					key = "i", -- Magit uses 'z' for both save and 'Z' for push? 'i' usually stash index?
                    -- Magit: z -> Save.
                    -- Let's stick to 'z'.
					cb = function(f)
                        -- Stash index?
                        M.save(f)
                    end,
					desc = "Save (legacy map)",
				},
			},
		},
		{
			title = "Manage",
			items = {
				{ key = "a", cb = M.apply, desc = "Apply" },
				{ key = "p", cb = M.pop, desc = "Pop" },
				{ key = "k", cb = M.drop, desc = "Drop" }, -- Magit uses 'k' for drop stash in list usually?
			},
		},
	}

	util.Map("n", "z", function()
		require("oz.util.help_keymaps").show_menu("Stash Actions", options)
	end, { buffer = buf, desc = "Stash Actions", nowait = true })
end

return M
