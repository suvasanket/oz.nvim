local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.apply()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if not stash then
		stash = s_util.get_stash_under_cursor().index and "stash@{" .. s_util.get_stash_under_cursor().index .. "}"
	end

	if stash then
		s_util.run_n_refresh("Git stash apply -q " .. stash)
	else
		-- Prompt
		local stash_id = util.UserInput("Stash index (0):")
		if stash_id == "" then
			stash_id = "0"
		end
		s_util.run_n_refresh("Git stash apply -q stash@{" .. stash_id .. "}")
	end
end

function M.pop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if not stash then
		stash = s_util.get_stash_under_cursor().index and "stash@{" .. s_util.get_stash_under_cursor().index .. "}"
	end

	if stash then
		s_util.run_n_refresh("Git stash pop -q " .. stash)
	else
		local stash_id = util.UserInput("Stash index (0):")
		if stash_id == "" then
			stash_id = "0"
		end
		s_util.run_n_refresh("Git stash pop -q stash@{" .. stash_id .. "}")
	end
end

function M.drop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if not stash then
		stash = s_util.get_stash_under_cursor().index and "stash@{" .. s_util.get_stash_under_cursor().index .. "}"
	end

	if stash then
		s_util.run_n_refresh("Git stash drop -q " .. stash)
	else
		local stash_id = util.UserInput("Stash index (0):")
		if stash_id == "" then
			stash_id = "0"
		end
		s_util.run_n_refresh("Git stash drop -q stash@{" .. stash_id .. "}")
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
	elseif args ~= "" then
		s_util.run_n_refresh("Git stash save" .. args)
	end
end

function M.snapshot()
	s_util.run_n_refresh("Git stash push -m 'Snapshot'")
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-u", name = "--include-untracked", type = "switch", desc = "Include untracked" },
				{ key = "-a", name = "--all", type = "switch", desc = "Include all (ignored)" },
				{ key = "-k", name = "--keep-index", type = "switch", desc = "Keep index" },
			},
		},
		{
			title = "Stash",
			items = {
				{ key = "z", cb = M.save, desc = "Stash" },
				{ key = "s", cb = M.snapshot, desc = "Snapshot" },
				{
					key = "i",
					cb = function(f)
						local flags = f or {}
						table.insert(flags, "--keep-index")
						M.save(flags)
					end,
					desc = "Stash index",
				}, -- Usually means stash but keep index?
			},
		},
		{
			title = "Manage",
			items = {
				{ key = "a", cb = M.apply, desc = "Apply" },
				{ key = "p", cb = M.pop, desc = "Pop" },
				{ key = "k", cb = M.drop, desc = "Drop" },
			},
		},
	}

	vim.keymap.set("n", "z", function()
		util.show_menu("Stash Actions", options)
	end, { buffer = buf, desc = "Stash Actions", nowait = true, silent = true })
end

return M
