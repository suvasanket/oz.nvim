local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local git = require("oz.git")
local wizard = require("oz.git.wizard")
local caching = require("oz.caching")

local status_grab_buffer = status.status_grab_buffer
local refresh = status.refresh_status_buf
local state = status.state
local buf_id = nil

-- map helper
local map = function(...)
	g_util.map(...)
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

-- ==================================
--  Named Functions for Keymap Actions
-- ==================================

local function handle_quit()
	vim.api.nvim_echo({ { "" } }, false, {})
	vim.cmd("close")
end

local function handle_toggle_diff_or_section()
	if not s_util.toggle_diff() then
		s_util.toggle_section()
	end
end

local function handle_stage()
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
		-- Consider using inactive_input or directly running if preferred
		vim.api.nvim_feedkeys(":Git add .", "n", false)
	end
end

local function handle_unstage()
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
end

local function handle_discard()
	local entries = s_util.get_file_under_cursor()
	if #entries > 0 then
		util.ShellCmd({ "git", "restore", unpack(entries) }, function()
			refresh()
		end, function()
			util.Notify("Cannot discard currently selected.", "error", "oz_git")
		end)
	end
end

local function handle_untrack()
	local entries = s_util.get_file_under_cursor()
	if #entries > 0 then
		util.ShellCmd({ "git", "rm", "--cached", unpack(entries) }, function()
			refresh()
		end, function()
			util.Notify("currently selected can't be removed from tracking.", "error", "oz_git")
		end)
	end
end

local function handle_rename()
	local branch = s_util.get_branch_under_cursor()
	local file = s_util.get_file_under_cursor(true)[1]

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
			run_n_refresh("Git mv " .. file .. " " .. new_name)
		end
	elseif branch then
		local new_name = util.UserInput("New name: ", branch)
		if new_name then
			run_n_refresh("Git branch -m " .. branch .. " " .. new_name)
		end
	end
end

local function handle_stash_apply()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		run_n_refresh("G stash apply -q " .. stash)
	end
end

local function handle_stash_pop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		run_n_refresh("G stash pop -q " .. stash)
	end
end

local function handle_stash_drop()
	local current_line = vim.api.nvim_get_current_line()
	local stash = current_line:match("^%s*(stash@{%d+})")
	if stash then
		run_n_refresh("G stash drop -q " .. stash)
	end
end

local function handle_commit()
	run_n_refresh("Git commit -q")
end

local function handle_commit_amend_no_edit()
	run_n_refresh("Git commit --amend --no-edit -q")
end

local function handle_commit_amend()
	run_n_refresh("Git commit --amend -q")
end

local function handle_enter_key()
	local entry = s_util.get_file_under_cursor()
	local branch_under_cursor = s_util.get_branch_under_cursor()
	if #entry > 0 then
		-- Check if file or directory exists before trying to edit
		if vim.fn.filereadable(entry[1]) == 1 or vim.fn.isdirectory(entry[1]) == 1 then
			vim.cmd.wincmd("k") -- Go to previous window (presumably the main editing window)
			vim.cmd("edit " .. entry[1])
		else
			util.Notify("Cannot open entry: " .. entry[1], "warn", "oz_git")
		end
	elseif branch_under_cursor then
		git.after_exec_complete(function(code, _, err)
			if code == 0 then
				refresh()
				vim.schedule(function()
					util.Notify("Checked out branch '" .. branch_under_cursor .. "'.", nil, "oz_git")
				end)
			else
				-- Assuming oz_git_win exists and is the intended error handler
				require("oz.git.oz_git_win").open_oz_git_win(err, nil, "stderr")
			end
		end, true)
		vim.cmd("Git checkout " .. branch_under_cursor)
	else
		local line = vim.api.nvim_get_current_line()
		local quoted_str = line:match('"([^"]+)"')
		if quoted_str then
			quoted_str = quoted_str:gsub("git", "Git"):gsub("<[^>]*>", "")
			g_util.set_cmdline(quoted_str)
		end
	end
end

local function handle_goto_log()
	vim.cmd("close") -- Close status window before opening log
	require("oz.git.git_log").commit_log({ level = 1, from = "Git" })
end

local function handle_goto_log_context()
	local branch = s_util.get_branch_under_cursor()
	local file = s_util.get_file_under_cursor(true)
	vim.cmd("close") -- Close status window
	if branch then
		require("oz.git.git_log").commit_log({ level = 1, from = "Git" }, { branch })
	elseif #file > 0 then
		require("oz.git.git_log").commit_log({ level = 1, from = "Git" }, { "--", unpack(file) })
	else
		-- Fallback if neither branch nor file found? Or just call the standard log?
		require("oz.git.git_log").commit_log({ level = 1, from = "Git" })
	end
end

local function handle_goto_unstaged()
	g_util.goto_str("Changes not staged for commit:")
end

local function handle_goto_staged()
	g_util.goto_str("Changes to be committed:")
end

local function handle_goto_untracked()
	g_util.goto_str("Untracked files:")
end

local function handle_diff_file_history()
	local cur_file = s_util.get_file_under_cursor()
	if #cur_file > 0 then
		if util.usercmd_exist("DiffviewFileHistory") then
			vim.cmd("DiffviewFileHistory " .. cur_file[1])
		else
			vim.cmd(("Git difftool -y HEAD -- %s"):format(cur_file[1]))
			vim.fn.timer_start(700, function()
				git.cleanup_git_jobs({ cmd = "difftool" })
			end)
		end
	end
end

local function handle_diff_file_changes()
	local cur_file = s_util.get_file_under_cursor()
	if #cur_file > 0 then
		if util.usercmd_exist("DiffviewOpen") then
			vim.cmd("DiffviewOpen --selected-file=" .. cur_file[1])
			vim.schedule(function()
				vim.cmd("DiffviewToggleFiles")
			end)
		else
			vim.cmd(("Git difftool -y HEAD -- %s"):format(cur_file[1]))
			vim.fn.timer_start(700, function()
				git.cleanup_git_jobs({ cmd = "difftool" })
			end)
		end
	end
end

local function handle_diff_remote()
	local current_branch = s_util.get_branch_under_cursor() or state.current_branch

	local cur_remote_branch_ref = util.ShellOutput(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))
	if cur_remote_branch_ref and cur_remote_branch_ref ~= "" then
		vim.cmd(("DiffviewOpen %s...%s"):format(cur_remote_branch_ref, current_branch))
	end
end

local function handle_diff_branch()
	local branch_under_cursor = s_util.get_branch_under_cursor()
	if branch_under_cursor then
		g_util.set_cmdline(("DiffviewOpen %s|...%s"):format(state.current_branch, branch_under_cursor))
	else
		g_util.set_cmdline(("DiffviewOpen %s|"):format(state.current_branch))
	end
end

local function handle_conflict_start_manual()
	vim.cmd("close") -- Close status window
	wizard.start_conflict_resolution()
	vim.notify_once(
		"]x / [x => jump between conflict marker.\n:CompleteConflictResolution => complete",
		vim.log.levels.INFO,
		{ title = "oz_git", timeout = 4000 }
	)

	-- Define command for completion within the resolution context
	vim.api.nvim_create_user_command("CompleteConflictResolution", function()
		wizard.complete_conflict_resolution()
		vim.api.nvim_del_user_command("CompleteConflictResolution") -- Clean up command
	end, {})
end

local function handle_conflict_complete()
	if wizard.on_conflict_resolution then
		wizard.complete_conflict_resolution()
		-- Maybe refresh status after completion? Or rely on wizard to handle it.
	else
		util.Notify("Start the resolution with 'xo' first.", "warn", "oz_git")
	end
end

local function handle_conflict_diffview()
	if util.usercmd_exist("DiffviewOpen") then
		vim.cmd("DiffviewOpen")
	else
		util.Notify("DiffviewOpen command not found.", "error", "oz_git")
	end
end

local function handle_toggle_pick()
	local line_content = vim.api.nvim_get_current_line()
	local entry = line_content:match("^%s*(stash@{%d+})") -- Check for stash first
	if not entry then
		entry = s_util.get_branch_under_cursor() or s_util.get_file_under_cursor(true)[1]
	end

	if not entry then
		util.Notify("Can only pick files, branches, or stashes.", "error", "oz_git")
		return
	end

	-- Logic for picking/unpicking
	if vim.tbl_contains(status_grab_buffer, entry) then
		-- Unpick
		if #status_grab_buffer > 1 then
			util.remove_from_tbl(status_grab_buffer, entry)
			vim.api.nvim_echo({ { ":Git | " }, { table.concat(status_grab_buffer, " "), "@attribute" } }, false, {})
		elseif status_grab_buffer[1] == entry then
			-- Last item, clear and stop monitoring
			util.tbl_monitor().stop_monitoring(status_grab_buffer)
			status_grab_buffer = {} -- Reassign to new empty table
			status.status_grab_buffer = status_grab_buffer -- Update original reference if needed
			vim.api.nvim_echo({ { "" } }, false, {})
		end
	else
		-- Pick
		util.tbl_insert(status_grab_buffer, entry) -- Add to existing table

		-- Start monitoring if it's the first item picked
		if #status_grab_buffer == 1 then
			util.tbl_monitor().start_monitoring(status_grab_buffer, {
				interval = 2000,
				buf = buf_id, -- Use captured buf_id
				on_active = function(t)
					vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
				end,
			})
		else
			-- Already monitoring, just update echo if needed
			vim.api.nvim_echo({ { ":Git | " }, { table.concat(status_grab_buffer, " "), "@attribute" } }, false, {})
		end
	end
end

local function handle_edit_picked()
	if #status_grab_buffer > 0 then
		util.tbl_monitor().stop_monitoring(status_grab_buffer)
		g_util.set_cmdline("Git | " .. table.concat(status_grab_buffer, " "))
		status_grab_buffer = {} -- Clear after editing
		status.status_grab_buffer = status_grab_buffer -- Update original reference
	end
end

local function handle_discard_picked()
	if #status_grab_buffer > 0 then
		util.tbl_monitor().stop_monitoring(status_grab_buffer)
		status_grab_buffer = {} -- Clear the buffer
		status.status_grab_buffer = status_grab_buffer -- Update original reference
		vim.api.nvim_echo({ { "" } }, false, {}) -- Clear echo area
	end
end

local function handle_remote_add_update()
	local initial_input = " "
	if util.ShellOutput("git remote") == "" then
		initial_input = " origin " -- Suggest 'origin' if no remotes exist
	end
	local input_str = util.inactive_input(":Git remote add", initial_input)

	if input_str then
		local args = g_util.parse_args(input_str)
		local remote_name = args[1]
		local remote_url = args[2]

		if remote_name and remote_url then
			local remotes = util.ShellOutputList("git remote")
			if vim.tbl_contains(remotes, remote_name) then
				-- Remote exists, ask to update URL
				local ans = util.prompt(
					"Remote '" .. remote_name .. "' already exists. Update URL?",
					"&Yes\n&No",
					2 -- Default to No
				)
				if ans == 1 then
					git.after_exec_complete(function(code)
						if code == 0 then
							util.Notify("Updated URL for remote '" .. remote_name .. "'.", nil, "oz_git")
							refresh() -- Refresh status potentially
						end
					end)
					vim.cmd("G remote set-url " .. remote_name .. " " .. remote_url)
				end
			else
				-- Add new remote
				git.after_exec_complete(function(code)
					if code == 0 then
						util.Notify("Added new remote '" .. remote_name .. "'.", nil, "oz_git")
						refresh() -- Refresh status potentially
					end
				end)
				vim.cmd("G remote add " .. remote_name .. " " .. remote_url)
			end
		else
			util.Notify("Requires remote name and URL.", "warn", "oz_git")
		end
	end
end

local function handle_remote_remove()
	local options = util.ShellOutputList("git remote")
	if #options == 0 then
		util.Notify("No remotes configured.", "info", "oz_git")
		return
	end

	vim.ui.select(options, { prompt = "Select remote to remove:" }, function(choice)
		if choice then
			-- Confirmation prompt
			local confirm_ans = util.prompt("Really remove remote '" .. choice .. "'?", "&Yes\n&No", 2)
			if confirm_ans == 1 then
				util.ShellCmd({ "git", "remote", "remove", choice }, function()
					util.Notify("Remote '" .. choice .. "' removed.", nil, "oz_git")
					refresh() -- Refresh status potentially
				end, function(err)
					util.Notify("Failed to remove remote '" .. choice .. "'. " .. (err or ""), "error", "oz_git")
				end)
			end
		end
	end)
end

local function handle_remote_rename()
	local options = util.ShellOutputList("git remote")
	if #options == 0 then
		util.Notify("No remotes to rename.", "info", "oz_git")
		return
	end

	vim.ui.select(options, { prompt = "Select remote to rename:" }, function(choice)
		if choice then
			local new_name = util.UserInput("New name for '" .. choice .. "':", choice)
			if new_name and new_name ~= choice then
				util.ShellCmd({ "git", "remote", "rename", choice, new_name }, function()
					util.Notify("Renamed remote '" .. choice .. "' to '" .. new_name .. "'.", nil, "oz_git")
					refresh() -- Refresh status potentially
				end, function(err)
					util.Notify("Failed to rename remote '" .. choice .. "'. " .. (err or ""), "error", "oz_git")
				end)
			elseif new_name == choice then
				util.Notify("New name is the same as the old name.", "info", "oz_git")
			end
		end
	end)
end

local function handle_push()
	local current_branch = s_util.get_branch_under_cursor() or state.current_branch

	if not current_branch then
		util.Notify("Could not determine current branch.", "error", "oz_git")
		return
	end

	local cur_remote = util.ShellOutput(string.format("git config --get branch.%s.remote", current_branch))
	local cur_remote_branch_ref = util.ShellOutput(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))
	local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$") or current_branch -- Fallback?

	local refined_args, branch

	if cur_remote_branch == state.current_branch then
		branch = cur_remote_branch
	else
		branch = current_branch .. ":" .. cur_remote_branch
	end

	if cur_remote_branch_ref == "" then
		local remote = util.ShellOutputList("git remote")[1]
		refined_args = "-u " .. remote .. " " .. current_branch
	else
		refined_args = string.format("%s %s", cur_remote, branch)
	end

	g_util.set_cmdline("Git " .. refined_args)
end

local function handle_pull()
	local current_branch = s_util.get_branch_under_cursor() or state.current_branch

	if not current_branch then
		util.Notify("Could not determine current branch.", "error", "oz_git")
		return
	end

	local cur_remote = util.ShellOutput(string.format("git config --get branch.%s.remote", current_branch))
	local cur_remote_branch_ref = util.ShellOutput(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))

	if cur_remote == "" or cur_remote_branch_ref == "" then
		util.Notify(
			"Upstream not configured for branch '" .. current_branch .. "'. Use 'bu' to set upstream.",
			"warn",
			"oz_git"
		)
		return
	end

	-- Extract remote branch name (handle potential errors/empty output)
	local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$") or current_branch -- Fallback?

	local branch

	if cur_remote_branch == state.current_branch then
		branch = cur_remote_branch
	else
		branch = cur_remote_branch .. ":" .. current_branch
	end

	g_util.set_cmdline(("Git pull %s %s"):format(cur_remote, branch))
end

local function handle_branch_new()
	local b_name = util.inactive_input(":Git branch ")
	if b_name and vim.trim(b_name) ~= "" then
		run_n_refresh("Git branch " .. b_name)
	elseif b_name == "" then
		util.Notify("Branch name cannot be empty.", "warn", "oz_git")
	end
end

local function handle_branch_delete()
	local branch = s_util.get_branch_under_cursor()
	if branch then
		if branch == state.current_branch then
			util.Notify("Cannot delete the current branch.", "error", "oz_git")
			return
		end
		local ans = util.prompt("Delete branch '" .. branch .. "'?", "&Yes\n&No", 2)
		if ans == 1 then
			-- Use -d for safe delete, maybe offer -D?
			run_n_refresh("Git branch -d " .. branch)
		end
	else
		util.Notify("Cursor not on a deletable branch.", "warn", "oz_git")
	end
end

local function handle_branch_set_upstream()
	local branch = s_util.get_branch_under_cursor()
	if not branch then
		util.Notify("Cursor not on a local branch.", "warn", "oz_git")
		return
	end

	local remote_branches_raw = util.ShellOutputList("git branch -r")
	local remote_branches = {}
	for _, rb in ipairs(remote_branches_raw) do
		local trimmed_rb = vim.trim(rb)
		-- Filter out 'HEAD ->' entries if they appear
		if not trimmed_rb:match("^HEAD ") then
			table.insert(remote_branches, trimmed_rb)
		end
	end

	if #remote_branches == 0 then
		util.Notify("No remote branches found.", "info", "oz_git")
		return
	end

	vim.ui.select(remote_branches, { prompt = "Select upstream branch for '" .. branch .. "':" }, function(choice)
		if choice then
			run_n_refresh("Git branch --set-upstream-to=" .. choice .. " " .. branch)
		end
	end)
end

local function handle_branch_unset_upstream()
	local branch = s_util.get_branch_under_cursor()
	if branch then
		local upstream = util.ShellOutput(string.format("git rev-parse --abbrev-ref %s@{u}", branch))
		if upstream == "" then
			util.Notify("Branch '" .. branch .. "' has no upstream configured.", "info", "oz_git")
			return
		end
		local ans = util.prompt("Unset upstream ('" .. upstream .. "') for branch '" .. branch .. "'?", "&Yes\n&No", 2)
		if ans == 1 then
			run_n_refresh("Git branch --unset-upstream " .. branch)
		end
	else
		util.Notify("Cursor not on a local branch.", "warn", "oz_git")
	end
end

local function handle_merge_branch(flag)
	local branch_under_cursor = s_util.get_branch_under_cursor()
	local key = "git_user_merge_flags"
	local json = "oz_git"
	if branch_under_cursor then
		local input
		if flag then
			input = util.inactive_input(":Git merge", " " .. flag .. " " .. branch_under_cursor)
		else
			input = util.inactive_input(":Git merge", " " .. branch_under_cursor)
		end
		if input then
			run_n_refresh("Git merge" .. input)
			input = input:gsub(flag, "")
			local flags_to_cache = util.extract_flags(input)
			caching.set_data(key, table.concat(flags_to_cache, " "), json)
		end
	end
end

local function handle_rebase_branch()
	local branch_under_cursor = s_util.get_branch_under_cursor()
	if branch_under_cursor then
		g_util.set_cmdline("Git rebase| " .. branch_under_cursor)
	end
end

local function handle_reset()
	local files = s_util.get_file_under_cursor(true)
	local branch = s_util.get_branch_under_cursor()
	if #files > 0 then
		g_util.set_cmdline(("Git reset %s|"):format(table.concat(files, " ")))
	elseif branch then
		g_util.set_cmdline(("Git reset %s|"):format(branch))
	else
		g_util.set_cmdline("Git reset")
	end
end

local function handle_show_help()
	local user_mappings = require("oz.git").user_config.mappings -- Get mappings at time of call
	util.Show_buf_keymaps({
		header_name = {
			["Pick mappings"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" },
			["Commit mappings"] = { "cc", "ca", "ce", "c<Space>", "c" },
			["Diff mappings"] = { "dd", "dc", "dm", "db" },
			["Tracking related mappings"] = { "s", "u", "K", "X" },
			["Goto mappings"] = { "gu", "gs", "gU", "gl", "gL", "g<Space>", "g?" }, -- Added gL
			["Remote mappings"] = { "Ma", "Md", "Mr", "M" }, -- Added mP
			["Quick actions"] = { "grn", "<Tab>", "<CR>" }, -- Added refresh, quit, pull
			["Conflict resolution mappings"] = { "xo", "xc", "xp" },
			["Stash mappings"] = { "zz", "za", "zp", "zd", "z<Space>", "z" },
			["Branch mappings"] = { "bn", "bd", "bu", "bU" },
			["Push/Pull mappings"] = { "p", "P" },
			["Merge mappings"] = { "mm", "ml", "ma", "ms", "me", "mq", "m<Space>" },
			["Rebase mappings"] = { "rr", "ri", "rl", "ra", "rq", "rk", "r<Space>" },
			["Reset mappings"] = { "UU", "Uu", "Us", "Ux" },
		},
		no_empty = true,
		subtext = { "[󰳽 represents the key is actionable for entry under cursor.]" },
	})
end

-- Helper to map specific help keys
local function map_help_key(key, title)
	map({ "n", "x" }, key, function()
		util.Show_buf_keymaps({ key = key, title = title })
	end, { buffer = buf_id })
end

-- =======================
--  Keymap Definitions
-- =======================
function M.keymaps_init(buf)
	buf_id = buf

	-- quit
	map("n", "q", handle_quit, { buffer = buf_id, desc = "Close git status buffer." })

	-- tab (toggle)
	map(
		"n",
		"<tab>",
		handle_toggle_diff_or_section,
		{ buffer = buf_id, desc = "Toggle headings / inline file diff.󰳽 " }
	)

	-- refresh
	map("n", "<C-r>", refresh, { buffer = buf_id, desc = "Refresh status buffer." })

	-- stage
	map(
		{ "n", "x" },
		"s",
		handle_stage,
		{ buffer = buf_id, desc = "Stage entry under cursor or selected entries.󰳽 " }
	)

	-- unstage
	map(
		{ "n", "x" },
		"u",
		handle_unstage,
		{ buffer = buf_id, desc = "Unstage entry under cursor or selected entries.󰳽 " }
	)

	-- discard
	map(
		{ "n", "x" },
		"X",
		handle_discard,
		{ buffer = buf_id, desc = "Discard entry under cursor or selected entries.󰳽 " }
	)

	-- untrack
	map({ "n", "x" }, "K", handle_untrack, { buffer = buf_id, desc = "Untrack file or selected files.󰳽 " })

	-- rename
	map("n", "grn", handle_rename, { buffer = buf_id, desc = "Rename file or branch under cursor.󰳽 " })

	-- [z]Stash mappings --TODO add stash branch
	-- stash apply
	map("n", "za", handle_stash_apply, { buffer = buf_id, desc = "Apply stash under cursor.󰳽 " })
	-- stash pop
	map("n", "zp", handle_stash_pop, { buffer = buf_id, desc = "Pop stash under cursor.󰳽 " })
	-- stash drop
	map("n", "zd", handle_stash_drop, { buffer = buf_id, desc = "Drop stash under cursor.󰳽 " })
	-- :Git stash
	map("n", "z<space>", ":Git stash ", { silent = false, buffer = buf_id, desc = "Populate cmdline with :Git stash." })
	-- stash save
	map("n", "zz", function()
		local input = util.inactive_input(":Git stash", " save ")
		if input then
			run_n_refresh("Git stash" .. input)
		end
	end, { buffer = buf_id, desc = "Stash save optionally add a message." })

	-- commit map
	map("n", "cc", handle_commit, { buffer = buf_id, desc = ":Git commit" })
	-- commit ammend --no edit
	map("n", "ce", handle_commit_amend_no_edit, { buffer = buf_id, desc = ":Git commit --amend --no-edit" })
	-- commit amend
	map("n", "ca", handle_commit_amend, { buffer = buf_id, desc = ":Git commit --amend" })
	-- G commit cmdline
	map(
		"n",
		"c<space>",
		":Git commit ",
		{ silent = false, buffer = buf_id, desc = "Populate cmdline with :Git commit." }
	) -- Direct command string mapping

	-- open current entry / switch branch
	map("n", "<cr>", handle_enter_key, { buffer = buf_id, desc = "open entry under cursor / switch branches.󰳽 " })

	-- [g]oto mode
	-- log
	map("n", "gl", handle_goto_log, { buffer = buf_id, desc = "goto commit logs." })
	map("n", "gL", handle_goto_log_context, { buffer = buf_id, desc = "goto commit logs for file/branch.󰳽 " })
	-- :Git
	map("n", "g<space>", ":Git ", { silent = false, buffer = buf_id, desc = "Populate cmdline with :Git." })
	-- sections
	map("n", "gu", handle_goto_unstaged, { buffer = buf_id, desc = "goto unstaged changes section." })
	map("n", "gs", handle_goto_staged, { buffer = buf_id, desc = "goto staged for commit section." })
	map("n", "gU", handle_goto_untracked, { buffer = buf_id, desc = "goto untracked files section." })

	-- [d]iff mode
	map("n", "dd", handle_diff_file_changes, { buffer = buf_id, desc = "Diff file changes.󰳽 " })
	if util.usercmd_exist("DiffviewOpen") or util.usercmd_exist("DiffviewFileHistory") then -- only diffview keymaps
		map("n", "dc", handle_diff_file_history, { buffer = buf_id, desc = "Diff file history.󰳽 " })
		map("n", "dm", handle_diff_remote, { buffer = buf_id, desc = "Diff between local and remote branch.󰳽 " })
		map("n", "db", handle_diff_branch, { buffer = buf_id, desc = "Diff between branches.󰳽 " })
	end

	-- Merge/Conflict helper
	if state.in_conflict then
		-- Notifications about conflict state
		if wizard.on_conflict_resolution_complete then
			vim.notify_once(
				"Conflict resolution marked as complete. Stage changes and commit.",
				vim.log.levels.INFO,
				{ title = "oz_git", timeout = 3000 }
			)
		else
			vim.notify_once(
				"File has conflicts. Press 'xo' (manual) or 'xp' (Diffview) to resolve.",
				vim.log.levels.INFO,
				{ title = "oz_git", timeout = 3000 }
			)
		end
		-- start resolution
		map("n", "xo", handle_conflict_start_manual, { buffer = buf_id, desc = "Start manual conflict resolution." })
		-- complete (manual)
		map("n", "xc", handle_conflict_complete, { buffer = buf_id, desc = "Complete manual conflict resolution." })
		-- diffview resolve
		if util.usercmd_exist("DiffviewOpen") then
			map(
				"n",
				"xp",
				handle_conflict_diffview,
				{ buffer = buf_id, desc = "Open Diffview for conflict resolution." }
			)
		end
	end

	-- Pick Mode
	local user_mappings = require("oz.git").user_config.mappings -- Ensure this is available
	map(
		"n",
		user_mappings.toggle_pick,
		handle_toggle_pick,
		{ nowait = true, buffer = buf_id, desc = "Pick/unpick file/branch/stash.󰳽 " }
	)
	map(
		"n",
		{ "a", "i" },
		handle_edit_picked,
		{ nowait = true, buffer = buf_id, desc = "Enter cmdline to edit picked." }
	)
	map(
		"n",
		user_mappings.unpick_all,
		handle_discard_picked,
		{ nowait = true, buffer = buf_id, desc = "Discard picked entries." }
	)

	-- Remote mappings
	map("n", "Ma", handle_remote_add_update, { buffer = buf_id, desc = "Add or update remotes." })
	map("n", "Md", handle_remote_remove, { buffer = buf_id, desc = "Remove remote.󰳽 " })
	map("n", "Mr", handle_remote_rename, { buffer = buf_id, desc = "Rename remote.󰳽 " })

	-- push / pull
	map(
		"n",
		"p",
		handle_pull,
		{ buffer = buf_id, desc = "Git pull or pull from branch under cursor with specified flags.󰳽 " }
	)
	map(
		"n",
		"P",
		handle_push,
		{ buffer = buf_id, desc = "Git push or push to branch under cursor with specified flags.󰳽 " }
	)

	-- [B]ranch mappings
	map("n", "bn", handle_branch_new, { buffer = buf_id, desc = "Create a new branch.󰳽 " })
	map("n", "bd", handle_branch_delete, { buffer = buf_id, desc = "Delete branch under cursor.󰳽 " })
	map("n", "bu", handle_branch_set_upstream, { buffer = buf_id, desc = "Set upstream for branch under cursor.󰳽 " })
	map(
		"n",
		"bU",
		handle_branch_unset_upstream,
		{ buffer = buf_id, desc = "Unset upstream for branch under cursor.󰳽 " }
	)

	-- [M]erge mappings
	map("n", "mm", handle_merge_branch, { buffer = buf_id, desc = "Start merge with branch under cursor.󰳽 " })
	map("n", "ml", function()
		run_n_refresh("Git merge --continue")
	end, { buffer = buf_id, desc = "Merge continue." })
	map("n", "ma", function()
		run_n_refresh("Git merge --abort")
	end, { buffer = buf_id, desc = "Merge abort." })
	map("n", "ms", function()
		handle_merge_branch("--squash")
	end, { buffer = buf_id, desc = "Merge with squash." })
	map("n", "me", function()
		handle_merge_branch("--no-commit")
	end, { buffer = buf_id, desc = "Merge with no-commit." })
	map("n", "mq", function()
		handle_merge_branch("--quit")
	end, { buffer = buf_id, desc = "Merge quit." })
	map("n", "m<space>", ":Git merge ", { silent = false, buffer = buf_id, desc = "Populate cmdline with Git merge." })

	-- [R]ebase mappings
	map("n", "rr", handle_rebase_branch, { buffer = buf, desc = "Rebase branch under cursor with provided args.󰳽 " })
	map("n", "ri", function()
		local branch_under_cursor = s_util.get_branch_under_cursor()
		if branch_under_cursor then
			run_n_refresh("Git rebase -i " .. branch_under_cursor)
		end
	end, { buffer = buf, desc = "Start interactive rebase with branch under cursor.󰳽 " })
	map("n", "rl", function()
		run_n_refresh("Git rebase --continue")
	end, { buffer = buf, desc = "Rebase continue." })
	map("n", "ra", function()
		run_n_refresh("Git rebase --abort")
	end, { buffer = buf, desc = "Rebase abort." })
	map("n", "rq", function()
		run_n_refresh("Git rebase --quit")
	end, { buffer = buf, desc = "Rebase quit." })
	map("n", "rk", function()
		run_n_refresh("Git rebase --skip")
	end, { buffer = buf, desc = "Rebase skip." })
	map("n", "re", function()
		run_n_refresh("Git rebase --edit-todo")
	end, { buffer = buf, desc = "Rebase edit todo." })
	map(
		"n",
		"r<space>",
		":Git rebase ",
		{ silent = false, buffer = buf_id, desc = "Populate cmdline with :Git rebase." }
	)

	-- [R]eset mappings
	map({ "n", "x" }, "UU", handle_reset, { buffer = buf, desc = "Reset file/branch.󰳽 " })
	map("n", "Us", function()
		run_n_refresh("Git reset --soft")
	end, { buffer = buf, desc = "Soft reset." })
	map("n", "Um", function()
		run_n_refresh("Git reset --mixed")
	end, { buffer = buf, desc = "Mixed reset." })
	map("n", "Uh", function()
		local confirm_ans = util.prompt("Do really really want to Git reset --hard ?", "&Yes\n&No", 2)
		if confirm_ans == 1 then
			run_n_refresh("Git reset --hard")
		end
	end, { buffer = buf, desc = "Hard reset(danger)." })

	-- help
	map("n", "g?", handle_show_help, { buffer = buf_id, desc = "Show all availble keymaps." })
	map_help_key("M", "Remote mappings")
	map_help_key("c", "Commit mappings")
	map_help_key("z", "Stash mappings")
	map_help_key("d", "Diff mappings")
	map_help_key("b", "Branch mappings")
	map_help_key("m", "Merge mappings")
	map_help_key("r", "Rebase mappings")
	map_help_key("U", "Reset mappings")
	-- map_help_key("g", "[g] mappings")
end -- End of M.keymaps_init

return M
