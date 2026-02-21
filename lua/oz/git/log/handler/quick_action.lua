local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local grab_hashs = log.grab_hashs
local commit_log = log.commit_log
local refresh = log.refresh_buf
local run_n_refresh = log_util.run_n_refresh
local clear_all_picked = log_util.clear_all_picked

local user_mappings = require("oz.git").user_config.mappings
local buf_id = nil

function M.quit()
	vim.api.nvim_echo({ { "" } }, false, {})
	if not pcall(vim.cmd.close) then
		vim.cmd.blast()
	end
end

function M.increase_log()
	vim.cmd("close")
	log.log_level = (log.log_level % 3) + 1
	commit_log({ level = log.log_level, from = log.comming_from })
end

function M.decrease_log()
	vim.cmd("close")
	local log_levels = { [1] = 3, [2] = 1, [3] = 2 }
	log.log_level = log_levels[log.log_level]
	commit_log({ level = log.log_level, from = log.comming_from })
end

function M.go_back()
	if log.comming_from then
		vim.cmd("close")
		vim.cmd(log.comming_from)
	end
end

function M.cmd_git()
	util.set_cmdline("Git ")
end

function M.reflog()
	vim.cmd("Git reflog")
end

function M.refresh()
	refresh()
end

function M.show_hash()
	local hash = get_selected_hash()
	if #hash > 0 then
        run_n_refresh("Git show " .. table.concat(hash, " "))
	end
end

function M.checkout()
	local hash = get_selected_hash()
	if #hash > 0 then
		run_n_refresh("Git checkout -q " .. hash[1])
	end
end

function M.toggle_pick()
	local entry = get_selected_hash()[1]
	if not entry then
		util.Notify("Nothing to pick", "error", "oz_git")
		return
	end

	-- unpick
	if vim.tbl_contains(grab_hashs, entry) then
		if #grab_hashs > 1 then
            util.setup_hls({ "OzActive" })
			util.remove_from_tbl(grab_hashs, entry)
			vim.api.nvim_echo({ { ":Git | " }, { table.concat(grab_hashs, " "), "OzActive" } }, false, {})
		elseif grab_hashs[1] == entry then
			util.stop_monitoring(grab_hashs)
			for k in pairs(grab_hashs) do
				grab_hashs[k] = nil
			end
			while #grab_hashs > 0 do
				table.remove(grab_hashs)
			end
			vim.api.nvim_echo({ { "" } }, false, {})
		end
	else
		-- pick
		util.tbl_insert(grab_hashs, entry)

		util.start_monitoring(grab_hashs, {
			interval = 2000,
			buf = buf_id,
			on_active = function(t)
                util.setup_hls({ "OzActive" })
				vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "OzActive" } }, false, {})
			end,
		})
	end
end

function M.edit_picked()
	if #grab_hashs ~= 0 then
		util.stop_monitoring(grab_hashs)
		util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
		for k in pairs(grab_hashs) do
			grab_hashs[k] = nil
		end
		while #grab_hashs > 0 do
			table.remove(grab_hashs)
		end
	end
end

function M.add_args()
	local input = util.UserInput("args:")
	if input then
		vim.cmd("close")
		commit_log({ level = 1 }, { input })
	end
end

function M.go_status()
	vim.cmd("close")
	vim.cmd("Git")
end

function M.setup_keymaps(buf, key_grp)
	buf_id = buf
	-- quick actions
	vim.keymap.set("n", "q", M.quit, { buffer = buf, desc = "Close git log buffer.", silent = true })
	-- increase
	vim.keymap.set("n", ">", M.increase_log, { buffer = buf, desc = "Increase log level.", silent = true })
	-- decrease
	vim.keymap.set("n", "<", M.decrease_log, { buffer = buf, desc = "Decrease log level.", silent = true })
	-- back
	vim.keymap.set("n", "<C-o>", M.go_back, { buffer = buf, desc = "Go back.", silent = true })
	-- :G
	vim.keymap.set("n", "-", M.cmd_git, { silent = false, buffer = buf, desc = "Open :Git " })
	vim.keymap.set("n", "I", M.reflog, { buffer = buf, desc = "Open reflog", silent = true })
	-- refresh
	vim.keymap.set("n", "<C-r>", M.refresh, { buffer = buf, desc = "Refresh commit log buffer.", silent = true })
	-- show current hash
	vim.keymap.set({ "n", "x" }, "<cr>", M.show_hash, { buffer = buf, desc = "Show current commit under cursor. <*>", silent = true })
	-- check out to a commit
	vim.keymap.set("n", "<C-CR>", M.checkout, { buffer = buf, desc = "Checkout to the commit under cursor. <*>", silent = true })
	key_grp["quick actions"] = { "<lt>", ">", "-", "<CR>", "<C-O>", "<C-CR>", "I", "<C-R>", "q" }

	-- goto mappings
	local g_options = {
		{
			title = "Goto",
			items = {
				{ key = ":", cb = M.add_args, desc = "Add args to log command" },
				{ key = "s", cb = M.go_status, desc = "Go to git status buffer" },
				{
					key = "g",
					cb = function()
						vim.cmd("normal! gg")
					end,
					desc = "Goto top of buffer",
				},
				{
					key = "?",
					cb = function()
						util.show_maps({
							group = key_grp,
							subtext = { "[<*> represents the key is actionable for the entry under cursor.]" },
							no_empty = true,
						})
					end,
					desc = "Show all available keymaps",
				},
			},
		},
	}

	vim.keymap.set("n", "g", function()
		util.show_menu("Goto Actions", g_options)
	end, { buffer = buf, desc = "Goto Actions", nowait = true, silent = true })

	-- pick hash
	vim.keymap.set(
		"n",
		user_mappings.toggle_pick,
		M.toggle_pick,
		{ buffer = buf, desc = "Pick or unpick any hash under cursor. <*>", silent = true }
	)

	-- edit picked
	util.Map("n", { "a", "i" }, M.edit_picked, { buffer = buf, desc = "Enter cmdline to edit picked hashes." })

	-- discard picked
	vim.keymap.set("n", user_mappings.unpick_all, clear_all_picked, { buffer = buf, desc = "Discard any picked hashes.", silent = true })
	key_grp["pick"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" }
end

return M
