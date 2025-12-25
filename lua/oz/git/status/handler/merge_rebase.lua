local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local wizard = require("oz.git.wizard")
local caching = require("oz.caching")

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

return M
