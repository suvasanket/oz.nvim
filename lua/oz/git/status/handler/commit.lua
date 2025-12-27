local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local shell = require("oz.util.shell")

function M.create(flags)
	local cmd = "Git commit"
	if flags and #flags > 0 then
		cmd = cmd .. " " .. table.concat(flags, " ")
	end
	s_util.run_n_refresh(cmd)
end

function M.amend_no_edit(flags)
	local cmd = "Git commit --amend --no-edit"
	if flags and #flags > 0 then
		cmd = cmd .. " " .. table.concat(flags, " ")
	end
	s_util.run_n_refresh(cmd)
end

function M.amend(flags)
	local cmd = "Git commit --amend"
	if flags and #flags > 0 then
		cmd = cmd .. " " .. table.concat(flags, " ")
	end
	s_util.run_n_refresh(cmd)
end

function M.reword()
	s_util.run_n_refresh("Git commit --amend --only")
end

function M.fixup()
	-- Simplification: Fixup HEAD
	s_util.run_n_refresh("Git commit --fixup=HEAD")
end

function M.squash()
	-- Simplification: Squash into HEAD
	s_util.run_n_refresh("Git commit --squash=HEAD")
end

function M.instant_fixup()
	s_util.run_n_refresh("Git commit --fixup=HEAD")
end

function M.undo()
	local ok, commit_ahead = shell.run_command("git rev-list --count @{u}..HEAD")
	local commit_ahead_n = ok and tonumber(commit_ahead[1]) or nil

	if commit_ahead_n == 0 then
		util.Notify("Commit already pushed, you should 'revert'.", "warn", "oz_git")
	else
		s_util.run_n_refresh("Git reset --soft HEAD~1")
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-s", name = "--signoff", type = "switch", desc = "Signoff" },
				{ key = "-n", name = "--no-verify", type = "switch", desc = "Bypass hooks" },
				{ key = "-q", name = "--quiet", type = "switch", desc = "Quiet", default = true },
				{ key = "-e", name = "--allow-empty", type = "switch", desc = "Allow empty" },
				{ key = "-a", name = "--all", type = "switch", desc = "All" },
			},
		},
		{
			title = "Commit",
			items = {
				{ key = "c", cb = M.create, desc = "Create a commit" },
			},
		},
		{
			title = "Edit",
			items = {
				{ key = "e", cb = M.amend_no_edit, desc = "Extend (Amend --no-edit)" },
				{ key = "a", cb = M.amend, desc = "Amend" },
				{ key = "w", cb = M.reword, desc = "Reword" },
			},
		},
		{
			title = "Fixup",
			items = {
				{ key = "f", cb = M.fixup, desc = "Fixup (HEAD)" },
				{ key = "s", cb = M.squash, desc = "Squash (HEAD)" },
				-- { key = "A", cb = M.augment, desc = "Augment" },
			},
		},
		{
			title = "Undo",
			items = {
				{ key = "u", cb = M.undo, desc = "Undo last commit" },
			},
		},
	}

	util.Map("n", "c", function()
		require("oz.util.help_keymaps").show_menu("Commit Actions", options)
	end, { buffer = buf, desc = "Commit Actions", nowait = true })
end

return M
