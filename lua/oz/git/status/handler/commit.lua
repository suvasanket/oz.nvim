local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local shell = require("oz.util.shell")

function M.create()
    s_util.run_n_refresh("Git commit -q")
end

function M.amend_no_edit()
    s_util.run_n_refresh("Git commit --amend --no-edit -q")
end

function M.amend()
    s_util.run_n_refresh("Git commit --amend -q")
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
			title = "Commit",
			items = {
				{ key = "c", cb = M.create, desc = "Create a commit" },
				{
					key = "<Space>",
					cb = function()
						util.set_cmdline("Git commit ")
					end,
					desc = "Populate cmdline with :Git commit",
				},
				{
					key = "w",
					cb = function()
						vim.cmd("Gcw")
					end,
					desc = "Populate cmdline with :Gcw",
				},
			},
		},
		{
			title = "Amend",
			items = {
				{ key = "e", cb = M.amend_no_edit, desc = "Ammend with --no-edit" },
				{ key = "a", cb = M.amend, desc = "Ammend previous commit" },
				{ key = "u", cb = M.undo, desc = "Undo last commit" },
			},
		},
	}

	util.Map("n", "c", function()
		require("oz.util.help_keymaps").show_menu("Commit Actions", options)
	end, { buffer = buf, desc = "Commit Actions", nowait = true })
end

return M
