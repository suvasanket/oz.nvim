local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local status = require("oz.git.status")

-- Add Worktree (ww)
function M.add(flags)
	local force = false
	if flags then
		for _, f in ipairs(flags) do
			if f == "--force" then
				force = true
			end
		end
	end

	local loc_options = {
		{ key = "p: Parent of root", value = "parent" },
		{ key = "t: This dir", value = "this" },
		{ key = "c: Custom path", value = "custom" },
	}

	util.pick(loc_options, {
		title = "Select Worktree Location Base",
		on_select = function(base_choice)
			if not base_choice then
				return
			end

			local base_path
			if base_choice == "parent" then
				base_path = vim.fn.fnamemodify(vim.fn.getcwd(), ":h")
			elseif base_choice == "this" then
				base_path = vim.fn.getcwd()
			elseif base_choice == "custom" then
				base_path = util.UserInput("Path: ", vim.fn.getcwd() .. "/", "dir")
			end

			if not base_path or base_path == "" then
				return
			end

			local name = util.UserInput("Worktree Name: ")
			if not name or name == "" then
				return
			end

			local final_path = base_path .. "/" .. name
			local branches = g_util.get_branch()
			table.insert(branches, 1, "HEAD")

			util.pick(branches, {
				title = "Select Branch/Commit",
				on_select = function(commit_ish)
					if not commit_ish then
						return
					end

					local cmd = string.format("Git worktree add %q", final_path)
					if force then
						cmd = cmd .. " --force"
					end

					if commit_ish ~= "HEAD" then
						cmd = cmd .. " " .. commit_ish
					end

					s_util.run_n_refresh(cmd)
				end,
			})
		end,
	})
end

function M.prune()
	s_util.run_n_refresh("Git worktree prune")
end

function M.repair()
	s_util.run_n_refresh("Git worktree repair")
end

local function get_selected_worktree_path()
	local wt = s_util.get_worktree_under_cursor()
	if wt and status.state.worktree_map[wt.path] then
		return status.state.worktree_map[wt.path]
	end
	return nil
end

function M.remove(flags)
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end

	local force = false
	if flags then
		for _, f in ipairs(flags) do
			if f == "--force" then
				force = true
			end
		end
	end

	local ans = util.prompt("Remove worktree '" .. path .. "'?", "&Yes\n&No", 2)
	if ans == 1 then
		local cmd = "Git worktree remove"
		if force then
			cmd = cmd .. " --force"
		end
		s_util.run_n_refresh(string.format("%s %q", cmd, path))
	end
end

function M.lock()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end
	s_util.run_n_refresh(string.format("Git worktree lock %q", path))
end

function M.unlock()
	local path = get_selected_worktree_path()
	if not path then
		util.Notify("No worktree selected.", "warn", "oz_git")
		return
	end
	s_util.run_n_refresh(string.format("Git worktree unlock %q", path))
end

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

function M.visit()
	local path = get_selected_worktree_path()
	if path then
		vim.cmd("tabnew")
		vim.cmd("lcd " .. vim.fn.fnameescape(path))
		vim.cmd("e .") -- open dir
		return
	end

	local worktrees = {}
	for name, p in pairs(status.state.worktree_map or {}) do
		table.insert(worktrees, { key = name, value = p })
	end

	if #worktrees == 0 then
		util.Notify("No worktrees found.", "warn", "oz_git")
		return
	end

	table.sort(worktrees, function(a, b)
		return a.key < b.key
	end)

	util.pick(worktrees, {
		title = "Visit Worktree",
		on_select = function(p)
			if p then
				vim.cmd("tabnew")
				vim.cmd("lcd " .. vim.fn.fnameescape(p))
				vim.cmd("e .")
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-f", name = "--force", type = "switch", desc = "Force" },
			},
		},
		{
			title = "Worktree",
			items = {
                { key = "W", cb = M.visit, desc = "Visit worktree" },
				{ key = "a", cb = M.add, desc = "Add new worktree" },
				{ key = "d", cb = M.remove, desc = "Delete worktree" },
				{ key = "m", cb = M.move, desc = "Move worktree" },
				{ key = "l", cb = M.lock, desc = "Lock worktree" },
				{ key = "u", cb = M.unlock, desc = "Unlock worktree" },
				{ key = "p", cb = M.prune, desc = "Prune worktrees" },
				{ key = "R", cb = M.repair, desc = "Repair worktrees" },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git worktree " .. flags .. " ")
					end,
					desc = "Worktree (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "W", function()
		util.show_menu("Worktree Actions", options)
	end, { buffer = buf, desc = "Worktree Actions", nowait = true, silent = true })
end

return M
