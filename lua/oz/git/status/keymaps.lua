local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local git = require("oz.git")
local wizard = require("oz.git.wizard")

local status_grab_buffer = status.status_grab_buffer
local refresh = status.refresh_status_buf

-- map --
local buf_id = nil
local map = g_util.map
local help_key = function(key, title)
	map("n", key, function()
		util.Show_buf_keymaps({
			key = key,
			title = title,
		})
	end, { buffer = buf_id })
end

local function run_n_refresh(cmd)
	git.after_exec_complete(function(code)
		if code == 0 then
			refresh()
		end
	end)
	vim.cmd(cmd)
end

-- here --
function M.keymaps_init(buf)
	buf_id = buf
	-- quit
	map("n", "q", function()
		vim.api.nvim_echo({ { "" } }, false, {})
		vim.cmd("close")
	end, { buffer = buf, desc = "close git status buffer." })

	-- tab
	map("n", "<tab>", function()
		if not s_util.toggle_diff() then
			s_util.toggle_section()
		end
	end, { buffer = buf, desc = "Toggle headings / inline file diff." })

	-- refresh
	map("n", "<C-r>", function()
		refresh()
	end, { buffer = buf, desc = "Refresh status buffer." })

	-- stage
	map({ "n", "x" }, "s", function()
		local entries = s_util.get_file_under_cursor()
		local current_line = vim.api.nvim_get_current_line()

		if #entries > 0 then
			util.ShellCmd({ "git", "add", unpack(entries) }, function()
				refresh()
			end, function()
				util.Notify("Cannot stage selected.", "error", "oz_git")
			end)
		elseif current_line:find("Changes not staged for commit:") then
			util.ShellCmd({ "git", "add", "-u" }, function()
				refresh()
			end, function()
				util.Notify("Cannot stage selected.", "error", "oz_git")
			end)
		elseif current_line:find("Untracked files:") then
			vim.api.nvim_feedkeys(":Git add .", "n", false)
		end
	end, { buffer = buf, desc = "stage entry under cursor or selected entries." })

	-- unstage
	map({ "n", "x" }, "u", function()
		local entries = s_util.get_file_under_cursor()
		local current_line = vim.api.nvim_get_current_line()

		if #entries > 0 then
			util.ShellCmd({ "git", "restore", "--staged", unpack(entries) }, function()
				refresh()
			end, function()
				util.Notify("Cannot unstage currently selected.", "error", "oz_git")
			end)
		elseif current_line:find("Changes to be committed:") then
			util.ShellCmd({ "git", "reset" }, function()
				refresh()
			end, function()
				util.Notify("Cannot unstage currently selected.", "error", "oz_git")
			end)
		end
	end, { buffer = buf, desc = "unstage entry under cursor or selected entries." })

	-- discard
	map({ "n", "x" }, "X", function()
		local entries = s_util.get_file_under_cursor()
		if #entries > 0 then
			util.ShellCmd({ "git", "restore", unpack(entries) }, function()
				refresh()
			end, function()
				util.Notify("Cannot discard currently selected.", "error", "oz_git")
			end)
		end
	end, { buffer = buf, desc = "discard entry under cursor or selected entries." })

	-- untrack
	map({ "n", "x" }, "K", function()
		local entries = s_util.get_file_under_cursor()
		if #entries > 0 then
			util.ShellCmd({ "git", "rm", "--cached", unpack(entries) }, function()
				refresh()
			end, function()
				util.Notify("currently selected can't be removed from tracking.", "error", "oz_git")
			end)
		end
	end, { buffer = buf, desc = "Untrack file or selected files." })

	-- rename
	map("n", "grn", function()
		local branch = s_util.get_branch_under_cursor()
		local file = s_util.get_file_under_cursor(true)[1]

		-- after complete
		if file or branch then
			git.after_exec_complete(function(code)
				if code == 0 then
					refresh()
				end
			end, true)
		end
		if file then
			local new_name = util.UserInput("New name: ", file)
			if new_name then
				vim.cmd("Git mv " .. file .. " " .. new_name)
			end
		elseif branch then
			local new_name = util.UserInput("New name: ", branch)
			if new_name then
				vim.cmd("Git branch -m " .. branch .. " " .. new_name)
			end
		end
	end, { buffer = buf, desc = "Rename file or branch under cursor." })

	-- stash mappings
	-- stash apply
	map("n", "za", function()
		local current_line = vim.api.nvim_get_current_line()
		local stash = current_line:match("^%s*(stash@{%d+})")
		if stash then
			run_n_refresh("G stash apply -q " .. stash)
		end
	end, { buffer = buf, desc = "Apply stash under cursor." })
	-- stash pop
	map("n", "zp", function()
		local current_line = vim.api.nvim_get_current_line()
		local stash = current_line:match("^%s*(stash@{%d+})")
		if stash then
			run_n_refresh("G stash pop -q " .. stash)
		end
	end, { buffer = buf, desc = "Pop stash under cursor." })
	-- stash drop
	map("n", "zd", function()
		local current_line = vim.api.nvim_get_current_line()
		local stash = current_line:match("^%s*(stash@{%d+})")
		if stash then
			run_n_refresh("G stash drop -q " .. stash)
		end
	end, { buffer = buf, desc = "Drop stash under cursor." })
	-- :G stash
	map("n", "z<space>", function()
		local input = util.inactive_input(":Git stash", " ")
		if input then
			run_n_refresh("Git stash " .. input)
		elseif input == "" then
			run_n_refresh("Git stash")
		end
	end, { silent = false, buffer = buf, desc = ":Git stash " })

	-- commit map
	map("n", "cc", function()
		run_n_refresh("Git commit")
	end, { buffer = buf, desc = ":Git commit" })

	-- commit ammend --no edit
	map("n", "ce", function()
		run_n_refresh("Git commit --amend --no-edit")
	end, { buffer = buf, desc = ":Git commit --amend --no-edit" })

	-- commit amend
	map("n", "ca", function()
		run_n_refresh("Git commit --amend")
	end, { buffer = buf, desc = ":Git commit --amend" })

	-- G commit
	map("n", "c<space>", ":Git commit ", { silent = false, buffer = buf, desc = "Open cmdline with :Git commit" })

	-- open current entry
	map("n", "<cr>", function()
		local entry = s_util.get_file_under_cursor()
		if #entry > 0 then
			if vim.fn.filereadable(entry[1]) == 1 or vim.fn.isdirectory(entry[1]) == 1 then
				vim.cmd.wincmd("p")
				vim.cmd("edit " .. entry[1])
			end
		else
			-- change branch
			local branch_under_cursor = s_util.get_branch_under_cursor()
			if branch_under_cursor then
				git.after_exec_complete(function(code, out, err)
					if code == 0 then
						refresh()
						vim.schedule(function()
							util.Notify("Checkout to '" .. branch_under_cursor .. "' branch.", nil, "oz_git")
						end)
					else
						util.Notify("Cannot checkout to '" .. branch_under_cursor .. "' branch", "error", "oz_git")
					end
				end, true)
				vim.cmd("Git checkout " .. branch_under_cursor)
			end
		end
	end, { buffer = buf, desc = "open entry under cursor / switch branches." })

	-- [g]oto mode
	-- log
	map("n", "gl", function()
		vim.cmd("close")
		require("oz.git.git_log").commit_log({ level = 1, from = "Git" })
	end, { buffer = buf, desc = "goto commit logs." })
	-- :Git
	map("n", "g<space>", function()
		local input = util.inactive_input(":Git", " ")
		if input then
			run_n_refresh("G " .. input)
		elseif input == "" then
			vim.cmd("Git")
		end
	end, { silent = false, buffer = buf, desc = ":Git <cmd>" })

	map("n", "gu", function()
		g_util.goto_str("Changes not staged for commit:")
	end, { buffer = buf, desc = "goto unstaged changes section." })
	map("n", "gs", function()
		g_util.goto_str("Changes to be committed:")
	end, { buffer = buf, desc = "goto staged for commit section." })
	map("n", "gU", function()
		g_util.goto_str("Untracked files:")
	end, { buffer = buf, desc = "goto untracked files section." })

	-- [d]iff mode
	-- diff file
	map("n", "dc", function()
		local cur_file = s_util.get_file_under_cursor()
		if #cur_file > 0 then
			if util.usercmd_exist("DiffviewFileHistory") then
				vim.cmd("DiffviewFileHistory " .. cur_file[1])
			else
				vim.cmd("Git diff " .. cur_file[1])
			end
		end
	end, { buffer = buf, desc = "diff of file under cursor throughout its commits." })

	map("n", "dd", function()
		local cur_file = s_util.get_file_under_cursor()
		if #cur_file > 0 then
			if util.usercmd_exist("DiffviewOpen") then
				vim.cmd("DiffviewOpen --selected-file=" .. cur_file[1])
				vim.schedule(function()
					vim.cmd("DiffviewToggleFiles")
				end)
			else
				vim.cmd("Git diff " .. cur_file[1])
			end
		end
	end, { buffer = buf, desc = "diff unstaged changes of file under cursor." })

	-- Merge helper
	if status.in_conflict then
		if wizard.on_conflict_resolution_complete then
			vim.notify_once(
				"Stage the changes then perform the commit.",
				vim.log.levels.INFO,
				{ title = "oz_git", timeout = 3000 }
			)
		else
			vim.notify_once(
				"Press 'xo' or 'xp' to start conflict resolution.",
				vim.log.levels.INFO,
				{ title = "oz_git", timeout = 3000 }
			)
		end
		-- start resolution
		map("n", "xo", function()
			vim.cmd("close")
			wizard.start_conflict_resolution()
			vim.notify_once(
				"]x / [x => jump between conflict marker.\n:CompleteConflictResolution => complete",
				vim.log.levels.INFO,
				{ title = "oz_git", timeout = 4000 }
			)

			vim.api.nvim_create_user_command("CompleteConflictResolution", function()
				wizard.complete_conflict_resolution()
				vim.api.nvim_del_user_command("CompleteConflictResolution")
			end, {})
		end, { buffer = buf, desc = "Start manual conflict resolution." })

		-- complete
		map("n", "xc", function()
			if wizard.on_conflict_resolution then
				wizard.complete_conflict_resolution()
			else
				util.Notify("Start the resolution with 'xo' first.", "warn", "oz_git")
			end
		end, { buffer = buf, desc = "Complete manual conflict resolution." })

		-- diffview
		if util.usercmd_exist("DiffviewOpen") then
			map("n", "xp", function()
				vim.cmd("DiffviewOpen")
			end, {

				buffer = buf,

				desc = "Open Diffview to perform conflict resolution.",
			})
		end
	end

	-- Pick Mode
	-- pick files
	local user_mappings = require("oz.git").user_config.mappings
	map("n", user_mappings.toggle_pick, function()
		local entry = vim.api.nvim_get_current_line():match("^%s*(stash@{%d+})")
		if not entry then
			entry = s_util.get_branch_under_cursor() or s_util.get_file_under_cursor(true)[1]
		end

		if not entry then
			util.Notify("You can only pick a file or branch", "error", "oz_git")
			return
		end

		-- unpick
		if util.str_in_tbl(entry, status_grab_buffer) then
			if #status_grab_buffer > 1 then
				util.remove_from_tbl(status_grab_buffer, entry)
				vim.api.nvim_echo({ { ":Git | " }, { table.concat(status_grab_buffer, " "), "@attribute" } }, false, {})
			elseif status_grab_buffer[1] == entry then
				util.tbl_monitor().stop_monitoring(status_grab_buffer)
				status_grab_buffer = {}
				vim.api.nvim_echo({ { "" } }, false, {})
			end
		else
			-- pick
			util.tbl_insert(status_grab_buffer, entry)

			util.tbl_monitor().start_monitoring(status_grab_buffer, {
				interval = 2000,
				buf = buf,
				on_active = function(t)
					vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
				end,
			})
		end
	end, { nowait = true, buffer = buf, desc = "Pick or unpick any file/dir/branch/stash under cursor." })

	-- edit picked
	map("n", { "a", "i" }, function()
		if #status_grab_buffer ~= 0 then
			util.tbl_monitor().stop_monitoring(status_grab_buffer)
			g_util.set_cmdline("Git | " .. table.concat(status_grab_buffer, " "))
			status_grab_buffer = {}
		end
	end, { nowait = true, buffer = buf, desc = "Enter cmdline to edit picked entries." })

	-- discard picked
	map("n", user_mappings.unpick_all, function()
		util.tbl_monitor().stop_monitoring(status_grab_buffer)

		status_grab_buffer = #status_grab_buffer > 0 and {} or status_grab_buffer
		vim.api.nvim_echo({ { "" } }, false, {})
	end, { nowait = true, buffer = buf, desc = "Discard any picked entries." })

	-- Remote mappings
	-- remote add
	map("n", "ma", function()
		local input = nil
		if util.ShellOutput("git remote") ~= "" then
			input = util.inactive_input(":Git remote add ")
		else
			input = util.inactive_input(":Git remote add ", "origin ")
		end

		if input then
			input = g_util.parse_args(input)
			local remote_name = input[1]
			local remote_url = input[2]

			if remote_name and remote_url then
				local remotes = util.ShellOutputList("git remote")
				if util.str_in_tbl(remote_name, remotes) then
					local ans =
						util.prompt("url for " .. remote_name .. " already exists, do you want to update?", "&Yes\n&No")
					if ans == 1 then
						git.after_exec_complete(function(code)
							if code == 0 then
								util.Notify("Url of '" .. remote_name .. "' has been updated.", nil, "oz_git")
							end
						end)
						vim.cmd("G remote set-url " .. remote_name .. " " .. remote_url)
					end
				else
					git.after_exec_complete(function(code)
						if code == 0 then
							util.Notify("A new remote '" .. remote_name .. "' added.", nil, "oz_git")
						end
					end)
					vim.cmd("G remote add " .. remote_name .. " " .. remote_url)
				end
			end
		end
	end, { buffer = buf, desc = "Add or update remotes." })

	-- remove remote
	map("n", "md", function()
		local options = util.ShellOutputList("git remote")

		vim.ui.select(options, {
			prompt = "select remote to delete:",
		}, function(choice)
			if choice then
				util.ShellCmd({ "git", "remote", "remove", choice }, function()
					util.Notify("Remote " .. choice .. " has been removed!", nil, "oz_git")
				end)
			end
		end)
	end, { buffer = buf, desc = "Remove remote." })

	-- rename remote
	map("n", "mr", function()
		local options = util.ShellOutputList("git remote")

		vim.ui.select(options, {
			prompt = "select remote to rename:",
		}, function(choice)
			if choice then
				local name = util.UserInput("New name: ", choice)
				if name then
					util.ShellCmd({ "git", "remote", "rename", choice, name }, function()
						util.Notify("Remote renamed from " .. choice .. " -> " .. name, nil, "oz_git")
					end)
				end
			end
		end)
	end, { buffer = buf, desc = "Rename remote." })

	-- remote push
	map("n", "mP", function()
		local branch = s_util.get_branch_under_cursor()
		if branch then
			local remote = util.ShellOutputList("git remote")
			local input = util.inactive_input(":Git push", " " .. remote[1] .. " " .. branch)
			if input then
				run_n_refresh("Git push " .. input)
			end
		else
			run_n_refresh("Git push")
		end
	end, { buffer = buf, desc = ":Git push or push to branch under cursor." })

	-- remote pull
	map("n", "mp", function()
		local branch = s_util.get_branch_under_cursor()
		if branch then
			local remote = util.ShellOutputList("git remote")
			local input = util.inactive_input(":Git pull", " " .. remote[1] .. " " .. branch)
			if input then
				run_n_refresh("Git pull " .. input)
			end
		else
			run_n_refresh("Git pull")
		end
	end, { buffer = buf, desc = ":Git pull or pull using branch under cursor." })

	-- remote fetch
	map("n", "mf", function()
		local branch = s_util.get_branch_under_cursor()
		if branch then
			local remote = util.ShellOutputList("git remote")
			local input = util.inactive_input(":Git fetch", " " .. remote[1] .. " " .. branch)
			if input then
				run_n_refresh("Git fetch " .. input)
			end
		else
			run_n_refresh("Git fetch")
		end
	end, { buffer = buf, desc = ":Git fetch or fetch using branch under cursor." })

	-- Branch mappings
	-- map("n", "bn", function ()
	--
	-- end, { buffer = buf, desc = ":Git fetch or fetch using branch under cursor." })

	-- help
	map("n", "g?", function()
		util.Show_buf_keymaps({
			header_name = {
				["Pick mappings"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" },
				["Commit mappings"] = { "cc", "ca", "ce", "c<Space>", "c" },
				["Diff mappings"] = { "dd", "dc", "de", "d" },
				["Tracking related mappings"] = { "s", "u", "K", "X" },
				["Goto mappings"] = { "gu", "gs", "gU", "gl", "g<Space>", "g?" },
				["Remote mappings"] = { "ma", "md", "mr", "mp", "mP", "mf", "m" },
				["Quick actions"] = { "grn", "<Tab>", "<CR>" },
				["Conflict resolution mappings"] = { "xo", "xc", "xp" },
				["Stash mappings"] = { "za", "zp", "zd", "z<Space>", "z" },
			},
			no_empty = true,
		})
	end, { buffer = buf, desc = "Show all availble keymaps." })

	help_key("m", "Remote mappings")
	help_key("c", "Commit mappings")
	help_key("z", "Stash mappings")
	help_key("d", "Diff mappings")
end

return M
