local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local status = require("oz.git.status")

local function get_branch(callback, opts)
	opts = opts or {}
	local branch = s_util.get_branch_under_cursor()
	if branch then
		callback(branch)
		return
	end
	local branches = g_util.get_branch(opts)
	util.pick(branches, {
		title = opts.title or "Select branch",
		on_select = function(choice)
			if choice then
				callback(choice)
			end
		end,
	})
end

function M.cc()
	get_branch(function(choice)
		s_util.run_n_refresh("Git! switch " .. choice)
	end, { title = "Switch branch" })
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
		get_branch(function(choice)
			if choice then
				s_util.run_n_refresh(string.format("Git switch -c %s %s", new_branch, choice))
			end
		end, { title = "From branch" })
	end
end

function M.delete()
	get_branch(function(branch)
		if branch == status.state.current_branch then
			util.Notify("Cannot delete the current branch.", "error", "oz_git")
			return
		end

		local del_options = {
			{ key = "l: Local", value = "local" },
			{ key = "r: Remote", value = "remote" },
			{ key = "b: Both", value = "both" },
		}

		util.pick(del_options, {
			title = "Delete branch '" .. branch .. "'",
			on_select = function(ans)
				if ans == "local" then
					s_util.run_n_refresh("Git branch -D " .. branch)
				elseif ans == "remote" then
					local cur_remote = util.shellout_str(string.format("git config --get branch.%s.remote", branch))
					if cur_remote == "" then
						cur_remote = "origin"
					end
					s_util.run_n_refresh(("Git push %s --delete %s"):format(cur_remote, branch))
				elseif ans == "both" then
					s_util.run_n_refresh("Git branch -D " .. branch)
					local cur_remote = util.shellout_str(string.format("git config --get branch.%s.remote", branch))
					if cur_remote == "" then
						cur_remote = "origin"
					end
					s_util.run_n_refresh(("Git push %s --delete %s"):format(cur_remote, branch))
				end
			end,
		})
	end, { title = "Delete branch" })
end

function M.set_upstream()
	get_branch(function(branch)
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
	end, { title = "Set upstream" })
end

function M.unset_upstream()
	get_branch(function(branch)
		local upstream = util.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", branch))
		if upstream == "" then
			util.Notify("Branch '" .. branch .. "' has no upstream configured.", "info", "oz_git")
			return
		end
		local ans = util.prompt("Unset upstream ('" .. upstream .. "') for branch '" .. branch .. "'?", "&Yes\n&No", 2)
		if ans == 1 then
			s_util.run_n_refresh("Git branch --unset-upstream " .. branch)
		end
	end, { title = "Unset upstream" })
end

function M.rename()
	get_branch(function(branch)
		local new_name = util.UserInput("New name: ", branch)
		if new_name then
			s_util.run_n_refresh(string.format("Git branch -m %s %s", branch, new_name))
		end
	end, { title = "Rename branch" })
end

function M.copy()
	get_branch(function(branch)
		local new_name = util.UserInput("Copy branch '" .. (branch or "") .. "' to: ")
		if new_name and new_name ~= "" then
			s_util.run_n_refresh(string.format("Git branch %s %s", new_name, branch or ""))
		end
	end, { title = "Copy branch" })
end

function M.reset()
	get_branch(function(branch)
		local targets = g_util.get_branch()
		util.pick(targets, {
			title = "Reset branch '" .. branch .. "' to",
			on_select = function(choice)
				if choice then
					s_util.run_n_refresh(string.format("Git branch -f %s %s", branch, choice))
				end
			end,
		})
	end, { title = "Reset branch" })
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-a", name = "--all", type = "switch", desc = "All" },
				{ key = "-r", name = "--remotes", type = "switch", desc = "Remotes" },
				{ key = "-f", name = "--force", type = "switch", desc = "Force" },
			},
		},
		{
			title = "Checkout",
			items = {
				{ key = "b", cb = M.cc, desc = "Checkout/Switch branch" },
				{ key = "c", cb = M.new_from, desc = "Checkout new branch" },
				{ key = "n", cb = M.new, desc = "Create a new branch" },
			},
		},
		{
			title = "Manipulation",
			items = {
				{ key = "d", cb = M.delete, desc = "Delete branch" },
				{ key = "r", cb = M.rename, desc = "Rename branch" },
				{ key = "y", cb = M.copy, desc = "Copy branch" },
				{ key = "x", cb = M.reset, desc = "Reset branch" },
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
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git branch " .. flags .. " ")
					end,
					desc = "Branch (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "b", function()
		util.show_menu("Branch Actions", options)
	end, { buffer = buf, desc = "Branch Actions", nowait = true, silent = true })
end

return M
