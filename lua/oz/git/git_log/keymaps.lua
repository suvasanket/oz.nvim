local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local git = require("oz.git")

local log_level = require("oz.git.git_log").log_level
local comming_from = require("oz.git.git_log").comming_from
local get_selected_hash = require("oz.git.git_log").get_selected_hash
local grab_hashs = require("oz.git.git_log").grab_hashs
local commit_log = require("oz.git.git_log").commit_log

local user_mappings = require("oz.git").user_config.mappings
local refresh = require("oz.git.git_log").refresh_commit_log
local map = g_util.map
local buf_id = nil

-- Helper to map specific help keys
local function map_help_key(key, title)
	map("n", key, function()
		util.Show_buf_keymaps({ key = key, title = title })
	end, { buffer = buf_id })
end

-- Helper to run Vim command and refresh status buffer on success
local function run_n_refresh(cmd)
	git.after_exec_complete(function(code)
		if code == 0 then
			refresh()
		end
	end)
	vim.api.nvim_set_hl(0, "ozInactivePrompt", { fg = "#757575" })
	vim.api.nvim_echo({ { ":" .. cmd, "ozInactivePrompt" } }, false, {})
	vim.cmd(cmd)
end

-- helper to clear picked
local function clear_all_picked()
	util.tbl_monitor().stop_monitoring(grab_hashs)

	grab_hashs = #grab_hashs > 0 and {} or grab_hashs
	vim.api.nvim_echo({ { "" } }, false, {})
end

-- helper: run upon current commit under cursor
local function cmd_upon_current_commit(callback)
	local hash = get_selected_hash()
	if #hash > 0 then
		callback(hash[1])
	end
end

-----------------
-- All keymaps --
-----------------

function M.keymaps_init(buf)
	buf_id = buf
	-- close
	map("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close git log buffer." })

	-- increase log level
	map("n", ">", function()
		vim.cmd("close")
		log_level = (log_level % 3) + 1
		commit_log({ level = log_level, from = comming_from })
	end, { buffer = buf, desc = "Increase log level." })

	-- decrease log level
	map("n", "<", function()
		vim.cmd("close")
		local log_levels = { [1] = 3, [2] = 1, [3] = 2 }
		log_level = log_levels[log_level]
		commit_log({ level = log_level, from = comming_from })
	end, { buffer = buf, desc = "Decrease log level." })

	-- back
	map("n", "<C-o>", function()
		if comming_from then
			vim.cmd("close")
			vim.cmd(comming_from)
		end
	end, { buffer = buf, desc = "Go back." })

	-- [G}oto mappings
	-- custom user args
	map("n", "g:", function()
		local input = util.UserInput("args:")
		if input then
			vim.cmd("close")
			commit_log({ level = 1 }, { input })
		end
	end, { buffer = buf, desc = "Add args to log command." })

	-- :Git
	map("n", "g<space>", ":Git ", { silent = false, buffer = buf, desc = "Open :Git " })
	map("n", "gs", function()
		vim.cmd("close")
		vim.cmd("Git")
	end, { buffer = buf, desc = "Go to git status buffer." })

	-- pick hash
	map("n", user_mappings.toggle_pick, function()
		local entry = get_selected_hash()[1]
		if not entry then
			util.Notify("Nothing to pick", "error", "oz_git")
			return
		end

		-- unpick
		if vim.tbl_contains(grab_hashs, entry) then
			if #grab_hashs > 1 then
				util.remove_from_tbl(grab_hashs, entry)
				vim.api.nvim_echo({ { ":Git | " }, { table.concat(grab_hashs, " "), "@attribute" } }, false, {})
			elseif grab_hashs[1] == entry then
				util.tbl_monitor().stop_monitoring(grab_hashs)
				grab_hashs = {}
				vim.api.nvim_echo({ { "" } }, false, {})
			end
		else
			-- pick
			util.tbl_insert(grab_hashs, entry)

			util.tbl_monitor().start_monitoring(grab_hashs, {
				interval = 2000,
				buf = buf,
				on_active = function(t)
					vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
				end,
			})
		end
	end, { buffer = buf, desc = "Pick or unpick any hash under cursor." })

	-- edit picked
	map("n", { "a", "i" }, function()
		if #grab_hashs ~= 0 then
			util.tbl_monitor().stop_monitoring(grab_hashs)
			g_util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
			grab_hashs = {}
		end
	end, { buffer = buf, desc = "Enter cmdline to edit picked hashes." })

	-- discard picked
	map("n", user_mappings.unpick_all, clear_all_picked, { buffer = buf, desc = "Discard any picked hashes." })

	-- [d]iff mode
	-- diff hash
	map("n", "dd", function()
		local cur_hash = get_selected_hash()
		if #cur_hash > 0 then
			if util.usercmd_exist("DiffviewOpen") then
				vim.cmd("DiffviewOpen " .. cur_hash[1])
			else
				vim.cmd("Git diff " .. cur_hash)
			end
		end
	end, { buffer = buf, desc = "diff the working tree against the commit under cursor." })

	map("n", "dc", function()
		local cur_hash = get_selected_hash()
		if #cur_hash > 0 then
			if util.usercmd_exist("DiffviewOpen") then
				vim.cmd("DiffviewOpen " .. cur_hash[1] .. "^!")
			else
				vim.cmd("Git show " .. cur_hash[1])
			end
		end
	end, { buffer = buf, desc = "Diff the changes introduced by commit under cursor." })

	-- diff range
	local diff_range_hash = {}
	map({ "n", "x" }, "dp", function() -- TODO add support for picked hash local hash -> picked
		local hashes = get_selected_hash()
		if #hashes > 1 then
			if util.usercmd_exist("DiffviewOpen") then
				vim.cmd("DiffviewOpen " .. hashes[1] .. ".." .. hashes[#hashes])
			else
				vim.cmd("Git diff " .. hashes[1] .. ".." .. hashes[#hashes])
			end
		elseif #hashes == 1 then
			vim.notify_once("press 'dp' on another to pick <end-commit-hash>.")
			util.tbl_insert(diff_range_hash, hashes[1])
			if #diff_range_hash == 2 then
				if util.usercmd_exist("DiffviewOpen") then
					vim.cmd("DiffviewOpen " .. diff_range_hash[1] .. ".." .. diff_range_hash[#diff_range_hash])
				else
					vim.cmd("Git diff " .. diff_range_hash[1] .. ".." .. diff_range_hash[#diff_range_hash])
				end
				diff_range_hash = {}
			end
		end
	end, { buffer = buf, desc = "Diff commits between a range of commits." })

	-- Rebase mappings
	-- inter rebase
	map("n", "ri", function()
		local current_hash = get_selected_hash()
		if #current_hash > 0 then
			run_n_refresh("Git rebase -i " .. current_hash[1] .. "^")
		end
	end, { buffer = buf, desc = "Start interactive rebase including commit under cursor." })

	-- rebase with pick
	map("n", "rr", function()
		local current_hash = get_selected_hash()
		if #current_hash == 1 then
			g_util.set_cmdline("Git rebase| " .. current_hash[1])
		end
	end, { buffer = buf, desc = "Rebase with commit under cursor." })

	-- rebase open in cmdline
	map("n", "r<space>", ":Git rebase ", { silent = false, buffer = buf, desc = "Populate cmdline with Git rebase." })

	map("n", "rc", function()
		run_n_refresh("Git rebase --continue")
	end, { buffer = buf, desc = "Rebase continue." })
	map("n", "ra", function()
		run_n_refresh("Git rebase --abort")
	end, { buffer = buf, desc = "Rebase abort." })
	map("n", "rq", function()
		run_n_refresh("Git rebase --quit")
	end, { buffer = buf, desc = "Rebase quit." })
	map("n", "rs", function()
		run_n_refresh("Git rebase --skip")
	end, { buffer = buf, desc = "Rebase skip." })
	map("n", "ro", function()
		local hash = get_selected_hash()
		if #hash > 0 then
			run_n_refresh("Git rebase -i --autosquash " .. hash[1] .. "^")
		end
	end, { buffer = buf, desc = "Start interactive rebase with commit under cursor(--autosquash)." })

	-- refresh
	map("n", "<C-r>", function()
		refresh()
	end, { buffer = buf, desc = "Refresh commit log buffer." })

	-- show current hash
	map({ "n", "x" }, "<cr>", function()
		local hash = get_selected_hash()
		if #hash > 0 then
			vim.cmd("Git show " .. table.concat(hash, " "))
		end
	end, { buffer = buf, desc = "Show current commit under cursor." })

	-- cherry-pick TODO add more option
	map({ "n", "x" }, "p", function()
		local input
		if #grab_hashs > 0 then
			input = " " .. table.concat(grab_hashs, " ")
		else
			local hash = get_selected_hash()
			if #hash == 1 then
				input = util.inactive_input(":Git cherry-pick", " " .. hash[1])
			elseif #hash == 2 then
				input = util.inactive_input(":Git cherry-pick", " " .. table.concat(hash, " "))
			elseif #hash > 2 then
				input = util.inactive_input(":Git cherry-pick", " " .. hash[1] .. ".." .. hash[#hash])
			end
		end
		if input then
			run_n_refresh("Git cherry-pick" .. input)
		end
		if #grab_hashs > 0 then
			clear_all_picked()
		end
	end, { buffer = buf, desc = "Cherry-pick commit under cursor." })

	-- [C]ommit mappings
	map("n", "cs", function()
		cmd_upon_current_commit(function(hash)
			run_n_refresh("Git commit --squash " .. hash)
		end)
	end, { buffer = buf, desc = "Create commit with commit under cursor(--squash)." })

	map("n", "cf", function()
		cmd_upon_current_commit(function(hash)
			run_n_refresh("Git commit --fixup " .. hash)
		end)
	end, { buffer = buf, desc = "Create commit with commit under cursor(--fixup)." })

	map("n", "cc", function()
		cmd_upon_current_commit(function(hash)
			g_util.set_cmdline("Git commit| " .. hash)
		end)
	end, { buffer = buf, desc = "Populate cmdline with Git commit followed by current hash." })

	map("n", "ce", function()
		cmd_upon_current_commit(function(hash)
			run_n_refresh(("Git commit -C %s -q"):format(hash))
		end)
	end, { buffer = buf, desc = "Create commit & reuse message from commit under cursor." })

	map("n", "ca", function()
		cmd_upon_current_commit(function(hash)
			run_n_refresh(("Git commit -c %s -q"):format(hash))
		end)
	end, { buffer = buf, desc = "Create commit & edit message from commit under cursor." })

	-- help
	map("n", "g?", function()
		util.Show_buf_keymaps({
			header_name = {
				["Pick mappings"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" },
				["Goto mappings"] = { "g:", "g<Space>", "g?", "gs" },
				["Diff mappings"] = { "dd", "dc", "dp" },
				["Rebase mappings"] = { "rr", "ri", "r<Space>", "rc", "ra", "rq", "rs", "ro" },
				["Commit/Cherry-pick mappings"] = { "cs", "cf", "cc", "ce", "ca" },
			},
			no_empty = true,
		})
	end, { buffer = buf, desc = "Show all availble keymaps." })
	map_help_key("d", "Diff mappings")
	map_help_key("r", "Rebase mappings")
	map_help_key("c", "Commit/Cherry-pick mappings")
end

return M
