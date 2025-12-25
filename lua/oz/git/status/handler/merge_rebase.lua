local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local wizard = require("oz.git.wizard")
local caching = require("oz.caching")
local status = require("oz.git.status")

function M.conflict_start_manual()
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

function M.conflict_complete()
	if wizard.on_conflict_resolution then
		wizard.complete_conflict_resolution()
		-- Maybe refresh status after completion? Or rely on wizard to handle it.
	else
		util.Notify("Start the resolution with 'xo' first.", "warn", "oz_git")
	end
end

function M.conflict_diffview()
	if util.usercmd_exist("DiffviewOpen") then
		vim.cmd("DiffviewOpen")
	else
		util.Notify("DiffviewOpen command not found.", "error", "oz_git")
	end
end

function M.merge_branch(flag)
	local branch_under_cursor = s_util.get_branch_under_cursor()
	local key, json, input = "git_user_merge_flags", "oz_git", nil
	flag = not flag and caching.get_data(key, json) or flag

	if branch_under_cursor then
		if flag then
			input = util.inactive_input(":Git merge", " " .. flag .. " " .. branch_under_cursor)
		else
			input = util.inactive_input(":Git merge", " " .. branch_under_cursor)
		end
		if input then
			s_util.run_n_refresh("Git merge" .. input)
			local flags_to_cache = util.extract_flags(input)
			caching.set_data(key, table.concat(flags_to_cache, " "), json)
		end
	end
end

function M.rebase_branch()
	local branch_under_cursor = s_util.get_branch_under_cursor()
	if branch_under_cursor then
		util.set_cmdline("Git rebase| " .. branch_under_cursor)
	end
end

function M.rebase_interactive()
	local branch_under_cursor = s_util.get_branch_under_cursor()
	if branch_under_cursor then
		s_util.run_n_refresh("Git rebase -i " .. branch_under_cursor)
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	-- merge mappings
	util.Map("n", "mm", M.merge_branch, { buffer = buf, desc = "Start merge with branch under cursor. <*>" })
	util.Map("n", "ml", function()
		s_util.run_n_refresh("Git merge --continue")
	end, { buffer = buf, desc = "Merge continue." })
	util.Map("n", "ma", function()
		s_util.run_n_refresh("Git merge --abort")
	end, { buffer = buf, desc = "Merge abort." })
	util.Map("n", "ms", function()
		M.merge_branch("--squash")
	end, { buffer = buf, desc = "Merge with squash." })
	util.Map("n", "me", function()
		M.merge_branch("--no-commit")
	end, { buffer = buf, desc = "Merge with no-commit." })
	util.Map("n", "mq", function()
		M.merge_branch("--quit")
	end, { buffer = buf, desc = "Merge quit." })
	util.Map("n", "m<space>", function()
		util.set_cmdline("Git merge ")
	end, { silent = false, buffer = buf, desc = "Populate cmdline with Git merge." })
	map_help_key("m", "merge")
	key_grp["merge[m]"] = { "mm", "ml", "ma", "ms", "me", "mq", "m<Space>" }

	-- [R]ebase mappings
	util.Map("n", "rr", M.rebase_branch, { buffer = buf, desc = "Rebase branch under cursor with provided args. <*>" })
	util.Map("n", "ri", M.rebase_interactive, {
		buffer = buf,
		desc = "Start interactive rebase with branch under cursor. <*>",
	})
	util.Map("n", "rl", function()
		s_util.run_n_refresh("Git rebase --continue")
	end, { buffer = buf, desc = "Rebase continue." })
	util.Map("n", "ra", function()
		s_util.run_n_refresh("Git rebase --abort")
	end, { buffer = buf, desc = "Rebase abort." })
	util.Map("n", "rq", function()
		s_util.run_n_refresh("Git rebase --quit")
	end, { buffer = buf, desc = "Rebase quit." })
	util.Map("n", "rk", function()
		s_util.run_n_refresh("Git rebase --skip")
	end, { buffer = buf, desc = "Rebase skip." })
	util.Map("n", "re", function()
		s_util.run_n_refresh("Git rebase --edit-todo")
	end, { buffer = buf, desc = "Rebase edit todo." })
	util.Map("n", "r<space>", function()
		util.set_cmdline("Git rebase ")
	end, { silent = false, buffer = buf, desc = "Populate cmdline with :Git rebase." })
	map_help_key("r", "rebase")
	key_grp["rebase[r]"] = { "rr", "ri", "rl", "ra", "rq", "rk", "re", "r<Space>" }

	-- Merge/Conflict helper
	if status.state.in_conflict then
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
		util.Map("n", "xo", M.conflict_start_manual, { buffer = buf, desc = "Start manual conflict resolution." })
		-- complete (manual)
		util.Map("n", "xc", M.conflict_complete, { buffer = buf, desc = "Complete manual conflict resolution." })
		-- diffview resolve
		if util.usercmd_exist("DiffviewOpen") then
			util.Map("n", "xp", M.conflict_diffview, { buffer = buf, desc = "Open Diffview for conflict resolution." })
		end
		map_help_key("x", "conflict resolution")
	end
	key_grp["conflict resolution[x]"] = { "xo", "xc", "xp" }
end

return M
