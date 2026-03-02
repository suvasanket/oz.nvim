local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local grab_hashs = log.grab_hashs
local run_n_refresh = log_util.run_n_refresh
local clear_all_picked = log_util.clear_all_picked

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.handle_cherrypick(flags)
	local args = get_args(flags)
	local input
	if #grab_hashs > 0 then
		input = args .. " " .. table.concat(grab_hashs, " ")
		clear_all_picked()
	else
		local hash = get_selected_hash()
		util.exit_visual()
		local default_args = (args ~= "") and args or " -x"
		if #hash == 1 then
			input = util.inactive_input(":Git cherry-pick", default_args .. " " .. hash[1])
		elseif #hash == 2 then
			input = util.inactive_input(":Git cherry-pick", default_args .. " " .. table.concat(hash, " "))
		elseif #hash > 2 then
			input = util.inactive_input(":Git cherry-pick", default_args .. " " .. hash[1] .. ".." .. hash[#hash])
		end
	end
	if input then
		run_n_refresh("Git cherry-pick" .. input)
	end
end

function M.harvest()
	local g_git = require("oz.util.git")
	local branches = g_git.get_branch()
	util.pick(branches, {
		title = "Harvest from branch",
		on_select = function(choice)
			if choice then
				util.win_close()
				log.commit_log({ level = 1, from = "Git" }, { choice, "--not", "HEAD" })
				util.Notify("Picking commits from " .. choice .. " that are not in HEAD", "info", "oz_git")
			end
		end,
	})
end

function M.show_sequence()
	if #grab_hashs == 0 then
		util.Notify("No commits picked.", "warn", "oz_git")
		return
	end
	local items = {}
	for i, h in ipairs(grab_hashs) do
		local commit_line = util.shellout_str("git log -1 --format='%h %s' " .. h)
		table.insert(items, string.format("%d. %s", i, commit_line))
	end
	util.pick(items, { title = "Picked Commits (Sequence)" })
end

function M.toggle_pick()
	local hashes = get_selected_hash()
	local log_mod = require("oz.git.log")
	local current_picks = log_mod.grab_hashs

	for _, h in ipairs(hashes) do
		local found_idx = nil
		for i, p in ipairs(current_picks) do
			if p == h then
				found_idx = i
				break
			end
		end

		if found_idx then
			table.remove(current_picks, found_idx)
		else
			table.insert(current_picks, h)
		end
	end

	log_mod.refresh_buf(true)
end

function M.abort()
	run_n_refresh("Git cherry-pick --abort")
end

function M.quit()
	run_n_refresh("Git cherry-pick --quit")
end

function M.continue()
	run_n_refresh("Git cherry-pick --continue")
end

function M.skip()
	run_n_refresh("Git cherry-pick --skip")
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-e", name = "--edit", type = "switch", desc = "Edit" },
				{ key = "-n", name = "--no-commit", type = "switch", desc = "No commit" },
				{ key = "-s", name = "--signoff", type = "switch", desc = "Signoff" },
				{ key = "-f", name = "--ff", type = "switch", desc = "Fast-forward" },
				{ key = "-x", name = "-x", type = "switch", desc = "Add '(cherry picked from...)'" },
				{ key = "-a", name = "--allow-empty", type = "switch", desc = "Allow empty" },
				{ key = "-k", name = "--keep-redundant-commits", type = "switch", desc = "Keep redundant" },
			},
		},
		{
			title = "Cherry Pick",
			items = {
				{ key = "Y", cb = M.toggle_pick, desc = "Toggle pick commit" },
				{ key = "P", cb = M.handle_cherrypick, desc = "Paste/Apply picked commits" },
				{ key = "h", cb = M.harvest, desc = "Harvest (pick from branch)" },
				{ key = "s", cb = M.show_sequence, desc = "Show sequence" },
				{ key = "x", cb = clear_all_picked, desc = "Clear all picked commits" },
			},
		},
		{
			title = "Actions",
			items = {
				{ key = "l", cb = M.continue, desc = "Cherry-pick continue" },
				{ key = "k", cb = M.skip, desc = "Cherry-pick skip" },
				{ key = "q", cb = M.abort, desc = "Cherry-pick abort" },
				{ key = "Q", cb = M.quit, desc = "Cherry-pick quit" },
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git cherry-pick " .. flags .. " ")
					end,
					desc = "Cherry-pick (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set({ "n", "x" }, "Y", function()
		util.show_menu("Cherry Pick Actions", options)
	end, { buffer = buf, desc = "Cherry Pick Actions", nowait = true, silent = true })
end

return M
