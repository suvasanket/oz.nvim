local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local status = require("oz.git.status")

-- Add Worktree (ww)
function M.add()
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
function M.remove()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end

	local ans = util.prompt("Remove worktree '" .. path .. "'?", "&Yes\n&No\n&Force", 2)
	if ans == 1 then
		s_util.run_n_refresh(string.format("Git worktree remove %q", path))
	elseif ans == 3 then
		s_util.run_n_refresh(string.format("Git worktree remove --force %q", path))
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
	util.Map("n", "ww", M.add, { buffer = buf, desc = "Add new worktree." })
	util.Map("n", "wd", M.remove, { buffer = buf, desc = "Remove worktree under cursor. <*>" })
	util.Map("n", "wp", M.prune, { buffer = buf, desc = "Prune worktrees." })
	util.Map("n", "wR", M.repair, { buffer = buf, desc = "Repair worktrees." })
	util.Map("n", "wl", M.lock, { buffer = buf, desc = "Lock worktree under cursor. <*>" })
	util.Map("n", "wu", M.unlock, { buffer = buf, desc = "Unlock worktree under cursor. <*>" })
	util.Map("n", "wm", M.move, { buffer = buf, desc = "Move worktree under cursor. <*>" })

	map_help_key("w", "worktree")
	key_grp["worktree[w]"] = { "ww", "wd", "wp", "wR", "wl", "wu", "wm" }
end

return M

