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
	local m_opts = {
		{
			title = "Merge",
			items = {
				{ key = "m", cb = M.merge_branch, desc = "Start merge with branch under cursor" },
				{
					key = "<Space>",
					cb = function()
						util.set_cmdline("Git merge ")
					end,
					desc = "Populate cmdline with Git merge",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "l",
					cb = function()
						s_util.run_n_refresh("Git merge --continue")
					end,
					desc = "Merge continue",
				},
				{
					key = "a",
					cb = function()
						s_util.run_n_refresh("Git merge --abort")
					end,
					desc = "Merge abort",
				},
				{
					key = "q",
					cb = function()
						M.merge_branch("--quit")
					end,
					desc = "Merge quit",
				},
			},
		},
		{
			title = "Options",
			items = {
				{
					key = "s",
					cb = function()
						M.merge_branch("--squash")
					end,
					desc = "Merge with squash",
				},
				{
					key = "e",
					cb = function()
						M.merge_branch("--no-commit")
					end,
					desc = "Merge with no-commit",
				},
			},
		},
	}
	util.Map("n", "m", function()
		require("oz.util.help_keymaps").show_menu("Merge Actions", m_opts)
	end, { buffer = buf, desc = "Merge Actions", nowait = true })

	-- [R]ebase mappings
	local r_opts = {
		{
			title = "Rebase",
			items = {
				{ key = "r", cb = M.rebase_branch, desc = "Rebase branch under cursor" },
				{ key = "i", cb = M.rebase_interactive, desc = "Start interactive rebase" },
				{
					key = "<Space>",
					cb = function()
						util.set_cmdline("Git rebase ")
					end,
					desc = "Populate cmdline with :Git rebase",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "l",
					cb = function()
						s_util.run_n_refresh("Git rebase --continue")
					end,
					desc = "Rebase continue",
				},
				{
					key = "a",
					cb = function()
						s_util.run_n_refresh("Git rebase --abort")
					end,
					desc = "Rebase abort",
				},
				{
					key = "q",
					cb = function()
						s_util.run_n_refresh("Git rebase --quit")
					end,
					desc = "Rebase quit",
				},
				{
					key = "k",
					cb = function()
						s_util.run_n_refresh("Git rebase --skip")
					end,
					desc = "Rebase skip",
				},
				{
					key = "e",
					cb = function()
						s_util.run_n_refresh("Git rebase --edit-todo")
					end,
					desc = "Rebase edit todo",
				},
			},
		},
	}
	util.Map("n", "r", function()
		require("oz.util.help_keymaps").show_menu("Rebase Actions", r_opts)
	end, { buffer = buf, desc = "Rebase Actions", nowait = true })

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
		
		local x_opts = {
			{
				title = "Resolve",
				items = {
					{ key = "o", cb = M.conflict_start_manual, desc = "Start manual conflict resolution" },
					{ key = "c", cb = M.conflict_complete, desc = "Complete manual conflict resolution" },
				},
			}
		}
		
		if util.usercmd_exist("DiffviewOpen") then
			table.insert(x_opts[1].items, { key = "p", cb = M.conflict_diffview, desc = "Open Diffview for conflict resolution" })
		end
		
		util.Map("n", "x", function()
			require("oz.util.help_keymaps").show_menu("Conflict Resolution", x_opts)
		end, { buffer = buf, desc = "Conflict Resolution", nowait = true })
	end
end

return M
