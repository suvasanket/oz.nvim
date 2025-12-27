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

function M.merge_branch(flags)
	local branch_under_cursor = s_util.get_branch_under_cursor()
    local flag_str = ""
    if flags and #flags > 0 then
        flag_str = " " .. table.concat(flags, " ")
    end

	if branch_under_cursor then
        -- Inactive input usually prompts user to confirm command
        -- Magit usually just executes if you select 'Merge', but 'inactive_input' allows edit.
        -- Let's populate it with flags.
		local input = util.inactive_input(":Git merge", flag_str .. " " .. branch_under_cursor)
		if input then
			s_util.run_n_refresh("Git merge" .. input)
            -- Caching might be less relevant if we use explicit switches, but let's keep it clean
            -- We just run it.
		end
	end
end

function M.rebase_branch(flags)
	local branch_under_cursor = s_util.get_branch_under_cursor()
    local flag_str = ""
    if flags and #flags > 0 then
        flag_str = " " .. table.concat(flags, " ")
    end
	if branch_under_cursor then
        -- Magit 'r' rebase on branch.
		s_util.run_n_refresh("Git rebase" .. flag_str .. " " .. branch_under_cursor)
	end
end

function M.rebase_interactive(flags)
	local branch_under_cursor = s_util.get_branch_under_cursor()
    local flag_str = ""
    if flags and #flags > 0 then
        flag_str = " " .. table.concat(flags, " ")
    end
	if branch_under_cursor then
		s_util.run_n_refresh("Git rebase -i" .. flag_str .. " " .. branch_under_cursor)
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	-- merge mappings
	local m_opts = {
        {
            title = "Switches",
            items = {
                { key = "-f", name = "--ff-only", type = "switch", desc = "Fast-forward only" },
                { key = "-n", name = "--no-ff", type = "switch", desc = "No fast-forward" },
                { key = "-s", name = "--squash", type = "switch", desc = "Squash" },
                { key = "-c", name = "--no-commit", type = "switch", desc = "No commit" },
            }
        },
		{
			title = "Merge",
			items = {
				{ key = "m", cb = M.merge_branch, desc = "Merge" },
				{
					key = "e",
					cb = function(f)
                        local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git merge " .. flags .. " ")
					end,
					desc = "Merge (edit cmd)",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "a",
					cb = function()
						s_util.run_n_refresh("Git merge --abort")
					end,
					desc = "Abort",
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
            title = "Switches",
            items = {
                { key = "-k", name = "--keep-base", type = "switch", desc = "Keep base" },
                { key = "-a", name = "--autosquash", type = "switch", desc = "Autosquash" },
                { key = "-S", name = "--autostash", type = "switch", desc = "Autostash" },
            }
        },
		{
			title = "Rebase",
			items = {
				{ key = "r", cb = M.rebase_branch, desc = "Rebase on..." },
				{ key = "i", cb = M.rebase_interactive, desc = "Interactive" },
				{
					key = "e",
					cb = function(f)
                        local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git rebase " .. flags .. " ")
					end,
					desc = "Rebase (edit cmd)",
				},
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "c",
					cb = function()
						s_util.run_n_refresh("Git rebase --continue")
					end,
					desc = "Continue",
				},
				{
					key = "s",
					cb = function()
						s_util.run_n_refresh("Git rebase --skip")
					end,
					desc = "Skip",
				},
				{
					key = "a",
					cb = function()
						s_util.run_n_refresh("Git rebase --abort")
					end,
					desc = "Abort",
				},
                {
					key = "t",
					cb = function()
						s_util.run_n_refresh("Git rebase --edit-todo")
					end,
					desc = "Edit todo",
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
