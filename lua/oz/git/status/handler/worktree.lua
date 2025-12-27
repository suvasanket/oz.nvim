local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local status = require("oz.git.status")

-- Add Worktree (ww)
function M.add(flags)
    local force = false
    if flags then
        for _, f in ipairs(flags) do
            if f == "--force" then force = true end
        end
    end
    
	-- 1. Location Selection using util.prompt (confirm dialog)
	local ans = util.prompt("Select Worktree Location Base", "&Parent of root\n&This dir\n&Custom path", 2)
	if not ans or ans == 0 then
		return
	end

	local base_path
	if ans == 1 then -- Parent Dir
		base_path = vim.fn.fnamemodify(vim.fn.getcwd(), ":h")
	elseif ans == 2 then -- Current Dir
		base_path = vim.fn.getcwd()
	elseif ans == 3 then -- Provide Path
		base_path = util.UserInput("Path: ", vim.fn.getcwd() .. "/", "dir")
	end

	if not base_path or base_path == "" then
		return
	end

	-- 2. Name
	local name = util.UserInput("Worktree Name: ")
	if not name or name == "" then
		return
	end

	local final_path = base_path .. "/" .. name

	-- 3. Branch/Commit
	local commit_ish = util.UserInput("Branch/Commit (empty for HEAD): ")
	if not commit_ish then
		return
	end -- Cancelled

	-- Construct Command
	local cmd = string.format("Git worktree add %q", final_path)
    if force then cmd = cmd .. " --force" end
    
	if commit_ish ~= "" then
		cmd = cmd .. " " .. commit_ish
	end

	s_util.run_n_refresh(cmd)
end

-- Prune (wp)
function M.prune()
	s_util.run_n_refresh("Git worktree prune")
end

-- Repair (wR) - Useful if worktrees were moved manually
function M.repair()
	s_util.run_n_refresh("Git worktree repair")
end

-- Helper to get selected worktree path
local function get_selected_worktree_path()
	local wt = s_util.get_worktree_under_cursor()
	if wt and status.state.worktree_map[wt.path] then
		return status.state.worktree_map[wt.path] -- Return full path
	end
	return nil
end

-- Remove (wd)
function M.remove(flags)
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end
    
    local force = false
    if flags then
        for _, f in ipairs(flags) do
            if f == "--force" then force = true end
        end
    end

	local ans = util.prompt("Remove worktree '" .. path .. "'?", "&Yes\n&No", 2)
	if ans == 1 then
        local cmd = "Git worktree remove"
        if force then cmd = cmd .. " --force" end
		s_util.run_n_refresh(string.format("%s %q", cmd, path))
	end
end

-- Lock (wl)
function M.lock()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end
	s_util.run_n_refresh(string.format("Git worktree lock %q", path))
end

-- Unlock (wu)
function M.unlock()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end
	s_util.run_n_refresh(string.format("Git worktree unlock %q", path))
end

-- Move (wm)
function M.move()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end

	local new_path = util.UserInput("New Path: ", path, "dir")
	if new_path and new_path ~= path then
		s_util.run_n_refresh(string.format("Git worktree move %q %q", path, new_path))
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
        {
            title = "Switches",
            items = {
                { key = "-f", name = "--force", type = "switch", desc = "Force" },
            }
        },
		{
			title = "Manage",
			items = {
				{ key = "w", cb = M.add, desc = "Add new worktree" },
				{ key = "d", cb = M.remove, desc = "Remove worktree" },
				{ key = "m", cb = M.move, desc = "Move worktree" },
				{ key = "l", cb = M.lock, desc = "Lock worktree" },
				{ key = "u", cb = M.unlock, desc = "Unlock worktree" },
			},
		},
		{
			title = "Maintenance",
			items = {
				{ key = "p", cb = M.prune, desc = "Prune worktrees" },
				{ key = "R", cb = M.repair, desc = "Repair worktrees" },
			},
		},
	}

	util.Map("n", "w", function()
		require("oz.util.help_keymaps").show_menu("Worktree Actions", options)
	end, { buffer = buf, desc = "Worktree Actions", nowait = true })
end

return M

