local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-c", name = "--no-checkout", desc = "Don't checkout", type = "switch" },
				{ key = "-p", name = "--first-parent", desc = "First parent", type = "switch" },
			},
		},
		{
			title = "Bisect",
			items = {
				{
					key = "B",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						local grab_hashs = require("oz.git.log").grab_hashs
						local cmd = "Git! bisect start " .. flags
						if #grab_hashs > 0 then
							cmd = cmd .. " " .. table.concat(grab_hashs, " ")
							log_util.clear_all_picked()
						end
						log_util.run_n_refresh(cmd)
					end,
					desc = "Start",
				},
				{
					key = "g",
					cb = function()
						log_util.cmd_upon_current_commit(function(hash)
							log_util.run_n_refresh("Git! bisect good " .. hash)
						end)
					end,
					desc = "Good",
				},
				{
					key = "b",
					cb = function()
						log_util.cmd_upon_current_commit(function(hash)
							log_util.run_n_refresh("Git! bisect bad " .. hash)
						end)
					end,
					desc = "Bad",
				},
				{
					key = "s",
					cb = function()
						log_util.cmd_upon_current_commit(function(hash)
							log_util.run_n_refresh("Git! bisect skip " .. hash)
						end)
					end,
					desc = "Skip",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "q",
					cb = function()
						log_util.run_n_refresh("Git! bisect reset")
					end,
					desc = "Reset",
				},
				{
					key = "r",
					cb = function()
						local script = util.UserInput("Run script:")
						if script and script ~= "" then
							log_util.run_n_refresh("Git! bisect run " .. script)
						end
					end,
					desc = "Run",
				},
				{
					key = "t",
					cb = function()
						log_util.run_n_refresh("Git! bisect terms")
					end,
					desc = "Terms",
				},
				{
					key = "v",
					cb = function()
						log_util.run_n_refresh("Git! bisect visualize")
					end,
					desc = "Visualize",
				},
				{
					key = "l",
					cb = function()
						log_util.run_n_refresh("Git! bisect log")
					end,
					desc = "Log",
				},
				{
					key = "p",
					cb = function()
						local logfile = util.inactive_input("Replay log: ", "", "file")
						if logfile and logfile ~= "" then
							log_util.run_n_refresh("Git! bisect replay " .. logfile)
						end
					end,
					desc = "Replay",
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
