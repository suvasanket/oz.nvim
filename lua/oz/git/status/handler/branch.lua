local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local status = require("oz.git.status")
local shell = require("oz.util.shell")

function M.switch()
	util.set_cmdline("Git switch ")
end

function M.new()
	local b_name = util.inactive_input(":Git branch ")
	if b_name and vim.trim(b_name) ~= "" then
		s_util.run_n_refresh("Git branch " .. b_name)
	elseif b_name == "" then
		util.Notify("Branch name cannot be empty.", "warn", "oz_git")
	end
end

function M.new_from()
	local branches = g_util.get_branch()
	local new_branch = util.UserInput("New Branch Name:")
	vim.ui.select(branches, { prompt = "From branch:" }, function(choice)
		if choice then
			s_util.run_n_refresh(string.format("Git switch -c %s %s", new_branch, choice))
		end
	end)
end

function M.delete()
	local branch = s_util.get_branch_under_cursor()
	if branch then
		if branch == status.state.current_branch then
			util.Notify("Cannot delete the current branch.", "error", "oz_git")
			return
		end
		local ans = util.prompt("Delete branch '" .. branch .. "'?", "&Local\n&Remote\n&Both\n&Nevermind", 4)
		if ans == 1 then
			s_util.run_n_refresh("Git branch -D " .. branch)
		elseif ans == 2 then
			local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", branch))
			s_util.run_n_refresh(("Git push %s --delete %s"):format(cur_remote, branch))
		elseif ans == 3 then
			s_util.run_n_refresh("Git branch -D " .. branch)
			local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", branch))
			s_util.run_n_refresh(("Git push %s --delete %s"):format(cur_remote, branch))
		end
	else
		util.Notify("Cursor not on a deletable branch.", "warn", "oz_git")
	end
end

function M.set_upstream()
	local branch = s_util.get_branch_under_cursor()
	if not branch then
		util.Notify("Cursor not on a local branch.", "warn", "oz_git")
		return
	end

	local remote_branches = g_util.get_branch({ rem = true })
	if #remote_branches == 0 then
		util.Notify("No remote branches found.", "info", "oz_git")
		return
	end

	vim.ui.select(remote_branches, { prompt = "Select upstream branch for '" .. branch .. "':" }, function(choice)
		if choice then
			s_util.run_n_refresh("Git branch --set-upstream-to=" .. choice .. " " .. branch)
		end
	end)
end

function M.unset_upstream()
	local branch = s_util.get_branch_under_cursor()
	if branch then
		local upstream = shell.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", branch))
		if upstream == "" then
			util.Notify("Branch '" .. branch .. "' has no upstream configured.", "info", "oz_git")
			return
		end
		local ans = util.prompt("Unset upstream ('" .. upstream .. "') for branch '" .. branch .. "'?", "&Yes\n&No", 2)
		if ans == 1 then
			s_util.run_n_refresh("Git branch --unset-upstream " .. branch)
		end
	else
		util.Notify("Cursor not on a local branch.", "warn", "oz_git")
	end
end

function M.rename()
	local branch = s_util.get_branch_under_cursor()
	local new_name = util.UserInput("New name: ", branch)
	if new_name then
		s_util.run_n_refresh(string.format("Git branch -m %s %s", branch, new_name))
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
        -- Magit Branch Popup
        {
            title = "Checkout",
            items = {
                { key = "b", cb = M.switch, desc = "Checkout/Switch branch" },
                { key = "l", cb = function() s_util.run_n_refresh("Git checkout -") end, desc = "Checkout local branch" }, -- Placeholder logic
            }
        },
		{
			title = "Creation",
			items = {
				{ key = "n", cb = M.new, desc = "Create a new branch" },
				{ key = "c", cb = M.new_from, desc = "Create new branch..." },
			},
		},
		{
			title = "Manipulation",
			items = {
				{ key = "k", cb = M.delete, desc = "Delete branch" },
				{ key = "r", cb = M.rename, desc = "Rename branch" },
                { key = "x", cb = function() s_util.run_n_refresh("Git branch --edit-description") end, desc = "Edit description" },
			},
		},
		{
			title = "Configure",
			items = {
				{ key = "u", cb = M.set_upstream, desc = "Set upstream" },
				{ key = "U", cb = M.unset_upstream, desc = "Unset upstream" },
			},
		},
	}

	util.Map("n", "b", function()
		require("oz.util.help_keymaps").show_menu("Branch Actions", options)
	end, { buffer = buf, desc = "Branch Actions", nowait = true })
end

return M
