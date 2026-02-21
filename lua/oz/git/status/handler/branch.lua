local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local status = require("oz.git.status")

function M.cc()
	util.set_cmdline("Git checkout ")
end

function M.checkout_local()
	local branches = g_util.get_branch({ rem = false })
	util.pick(branches, {
		title = "Checkout branch",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git switch " .. choice)
			end
		end,
	})
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
	local branches = util.shellout_tbl("git for-each-ref --format=%(refname:short) refs/heads/ refs/remotes/")
	local new_branch = util.UserInput("New Branch Name:")
	if new_branch then
		util.pick(branches, {
			title = "From branch",
			on_select = function(choice)
				if choice then
					s_util.run_n_refresh(string.format("Git switch -c %s %s", new_branch, choice))
				end
			end,
		})
	end
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
			local cur_remote = util.shellout_str(string.format("git config --get branch.%s.remote", branch))
			if cur_remote == "" then
				cur_remote = "origin"
			end
			s_util.run_n_refresh(("Git push %s --delete %s"):format(cur_remote, branch))
		elseif ans == 3 then
			s_util.run_n_refresh("Git branch -D " .. branch)
			local cur_remote = util.shellout_str(string.format("git config --get branch.%s.remote", branch))
			if cur_remote == "" then
				cur_remote = "origin"
			end
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

	util.pick(remote_branches, {
		title = "Select upstream branch for '" .. branch .. "'",
		on_select = function(choice)
			if choice then
				s_util.run_n_refresh("Git branch --set-upstream-to=" .. choice .. " " .. branch)
			end
		end,
	})
end

function M.unset_upstream()
	local branch = s_util.get_branch_under_cursor()
	if branch then
		local upstream = util.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", branch))
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

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Checkout",
			items = {
				{ key = "b", cb = M.cc, desc = "Checkout/Switch branch" },
				{ key = "l", cb = M.checkout_local, desc = "Checkout local branch" },
			},
		},
		{
			title = "Creation",
			items = {
                { key = "c", cb = M.new_from, desc = "Checkout new branch" },
				{ key = "n", cb = M.new, desc = "Create a new branch" },
			},
		},
		{
			title = "Manipulation",
			items = {
				{ key = "d", cb = M.delete, desc = "Delete branch" },
				{ key = "r", cb = M.rename, desc = "Rename branch" },
				{
					key = "e",
					cb = function()
						s_util.run_n_refresh("Git branch --edit-description")
					end,
					desc = "Edit description",
				},
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

	vim.keymap.set("n", "b", function()
		util.show_menu("Branch Actions", options)
	end, { buffer = buf, desc = "Branch Actions", nowait = true, silent = true })
end

return M
