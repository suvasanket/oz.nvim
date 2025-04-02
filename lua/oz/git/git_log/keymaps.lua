local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")

local log_level = require("oz.git.git_log").log_level
local comming_from = require("oz.git.git_log").comming_from
local get_selected_hash = require("oz.git.git_log").get_selected_hash
local grab_hashs = require("oz.git.git_log").grab_hashs

local user_mappings = require("oz.git").user_config.mappings
local map = g_util.map

function M.keymaps_init(buf)
	-- close
	map("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close git log buffer." })

	-- increase log level
	map("n", ">", function()
		vim.cmd("close")
		log_level = (log_level % 3) + 1
		M.commit_log({ level = log_level, from = comming_from })
	end, { buffer = buf, desc = "Increase log level." })

	-- decrease log level
	map("n", "<", function()
		vim.cmd("close")
		local log_levels = { [1] = 3, [2] = 1, [3] = 2 }
		log_level = log_levels[log_level]
		M.commit_log({ level = log_level, from = comming_from })
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
			M.commit_log({ level = 1 }, { input })
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
		if util.str_in_tbl(entry, grab_hashs) then
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
	map("n", "a", function()
		if #grab_hashs ~= 0 then
			require("oz.git").after_exec_complete(function(code, stdout)
				if code == 0 and #stdout == 0 then
					M.refresh_commit_log()
				end
			end)
			util.tbl_monitor().stop_monitoring(grab_hashs)
			g_util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
			grab_hashs = {}
		end
	end, { buffer = buf, desc = "Enter cmdline to edit picked hashes." })

	map("n", "i", function()
		if #grab_hashs ~= 0 then
			require("oz.git").after_exec_complete(function(code, stdout)
				if code == 0 and #stdout == 0 then
					M.refresh_commit_log()
				end
			end)
			util.tbl_monitor().stop_monitoring(grab_hashs)
			g_util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
			grab_hashs = {}
		end
	end, { buffer = buf, desc = "Enter cmdline to edit picked hashes." })

	-- discard picked
	map("n", user_mappings.unpick_all, function()
		util.tbl_monitor().stop_monitoring(grab_hashs)

		grab_hashs = #grab_hashs > 0 and {} or grab_hashs
		vim.api.nvim_echo({ { "" } }, false, {})
	end, { buffer = buf, desc = "Discard any picked hashes." })

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
	map({ "n", "x" }, "dp", function()
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
		if #current_hash == 1 then
			vim.cmd("close")
			vim.cmd("Git rebase -i " .. current_hash[1] .. "^")
		end
	end, { buffer = buf, desc = "Start an interactive rebase inluding the commit under cursor." })

	-- rebase with pick
	map("n", "rp", function()
		local current_hash = get_selected_hash()
		if #current_hash == 1 then
			g_util.set_cmdline("Git rebase | " .. current_hash[1])
		end
	end, { buffer = buf, desc = "Open cmdline with rebase command with the commit hash under cursor." })

	-- rebase open in cmdline
	map("n", "r<space>", ":Git rebase ", { silent = false, buffer = buf, desc = ":Git rebase" })

	map("n", "rc", ":Git rebase --continue", { buffer = buf, desc = ":Git rebase --continue" })
	map("n", "ra", ":Git rebase --abort", { buffer = buf, desc = ":Git rebase --abort" })
	map("n", "rq", ":Git rebase --quit", { buffer = buf, desc = ":Git rebase --quit" })
	map("n", "rs", ":Git rebase --skip", { buffer = buf, desc = ":Git rebase --skip" })

	-- refresh
	map("n", "<C-r>", function()
		M.refresh_commit_log()
	end, { buffer = buf, desc = "Refresh commit log buffer." })

	-- show current hash
	map("n", "<cr>", function()
		local hash = get_selected_hash()
		if #hash > 0 then
			vim.cmd("Git show " .. hash[1])
		end
	end, { buffer = buf, desc = "Show current commit under cursor." })

	-- help
	map("n", "g?", function()
		util.Show_buf_keymaps({
			header_name = {
				["Pick mappings"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" },
				["Goto mappings"] = { "g:", "g<Space>", "g?", "gs" },
				["Diff mappings"] = { "dd", "dc", "dp" },
				["Rebase mappings"] = { "ri", "rp", "r<Space>", "rc", "ra", "rq", "rs" },
			},
		})
	end, { buffer = buf, desc = "Show all availble keymaps." })
end

return M
