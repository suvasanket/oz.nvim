local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

function M.reset(args)
    -- args is a string like "--soft" or nil
	local files = s_util.get_file_under_cursor(true)
	local branch = s_util.get_branch_under_cursor()
    
    local cmd_args = args or ""
	
    -- Logic: If files selected, reset files (mixed/hard not applicable usually to files with commit? Wait.
    -- git reset [commit] -- paths
    -- If files, we usually unstage.
    -- If branch/commit, we reset HEAD.
    
    local target = "HEAD" -- default
    
    if #files > 0 then
        -- Resetting files: "git reset [tree-ish] -- files"
        -- This usually unstages.
        -- If 'args' passed (like --soft), it might be invalid for paths?
        -- `git reset --soft HEAD -- file` -> error.
        -- `git reset HEAD -- file` -> mixed (default).
        -- So for files, we ignore mode flags usually?
        -- Magit 'Reset' on file usually means unstage.
        s_util.run_n_refresh("Git reset " .. table.concat(files, " "))
        return
    elseif branch then
        target = branch
    end
    
    -- Prompt for target if needed, or use target?
    -- Magit prompts "Reset to:".
    
    local input = util.inactive_input("Reset " .. (args or "mixed") .. " to:", target)
    if input then
        s_util.run_n_refresh("Git reset " .. cmd_args .. " " .. input)
    end
end

function M.undo_orig_head()
	s_util.run_n_refresh("Git reset ORIG_HEAD")
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
		{
			title = "Reset",
			items = {
				{ key = "s", cb = function() M.reset("--soft") end, desc = "Soft (keep worktree & index)" },
				{ key = "m", cb = function() M.reset("--mixed") end, desc = "Mixed (keep worktree)" },
				{ key = "h", cb = function() M.reset("--hard") end, desc = "Hard (discard all)" },
                { key = "k", cb = function() M.reset("--keep") end, desc = "Keep (safe)" },
			},
		},
        {
            title = "Utilities",
            items = {
                { key = "p", cb = M.undo_orig_head, desc = "Reset to ORIG_HEAD" },
                { key = "f", cb = function() M.reset(nil) end, desc = "Reset file/HEAD (Mixed)" },
            }
        }
	}
	util.Map("n", "X", function()
		require("oz.util.help_keymaps").show_menu("Reset Actions", options)
	end, { buffer = buf, desc = "Reset Actions", nowait = true })

	util.Map("x", "X", M.reset, { buffer = buf, desc = "Reset selection" })
end

return M
