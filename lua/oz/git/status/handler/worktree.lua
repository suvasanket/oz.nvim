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
	-- git worktree add <path> [commit-ish]
	-- If commit-ish is provided, it checks it out.
	-- If implicit, it tries to create a branch from HEAD with the name of the directory (dwim).
	local cmd = { "git", "worktree", "add", final_path }
	if commit_ish ~= "" then
		table.insert(cmd, commit_ish)
	end

	util.ShellCmd(cmd, function()
		util.Notify("Worktree created at " .. final_path, nil, "oz_git")
		status.refresh_buf()
	end, function()
		util.Notify("Failed to create worktree.", "error", "oz_git")
	end)
end

-- Prune (wp)
function M.prune()
	util.ShellCmd({ "git", "worktree", "prune" }, function()
		util.Notify("Worktrees pruned.", nil, "oz_git")
		status.refresh_buf()
	end)
end

-- Repair (wR) - Useful if worktrees were moved manually
function M.repair()
	util.ShellCmd({ "git", "worktree", "repair" }, function()
		util.Notify("Worktrees repaired.", nil, "oz_git")
		status.refresh_buf()
	end, function()
		util.Notify("Failed to repair worktrees.", "error", "oz_git")
	end)
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
		util.ShellCmd({ "git", "worktree", "remove", path }, function()
			util.Notify("Worktree removed.", nil, "oz_git")
			status.refresh_buf()
		end, function()
			util.Notify("Failed to remove worktree.", "error", "oz_git")
		end)
	elseif ans == 3 then
		util.ShellCmd({ "git", "worktree", "remove", "--force", path }, function()
			util.Notify("Worktree force removed.", nil, "oz_git")
			status.refresh_buf()
		end, function()
			util.Notify("Failed to remove worktree.", "error", "oz_git")
		end)
	end
end

-- Lock (wl)
function M.lock()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end
	util.ShellCmd({ "git", "worktree", "lock", path }, function()
		util.Notify("Worktree locked.", nil, "oz_git")
		status.refresh_buf()
	end)
end

-- Unlock (wu)
function M.unlock()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end
	util.ShellCmd({ "git", "worktree", "unlock", path }, function()
		util.Notify("Worktree unlocked.", nil, "oz_git")
		status.refresh_buf()
	end)
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
		util.ShellCmd({ "git", "worktree", "move", path, new_path }, function()
			util.Notify("Worktree moved.", nil, "oz_git")
			status.refresh_buf()
		end, function()
			util.Notify("Failed to move worktree.", "error", "oz_git")
		end)
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

