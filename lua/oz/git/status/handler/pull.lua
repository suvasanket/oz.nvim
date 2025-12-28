local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local shell = require("oz.util.shell")

local state = status.state

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.pull_cmd()
	local current_branch = s_util.get_branch_under_cursor() or state.current_branch

	if not current_branch then
		util.Notify("could not determine current branch.", "error", "oz_git")
		return
	end

	local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", current_branch))
	local cur_remote_branch_ref = shell.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))

	if cur_remote == "" or cur_remote_branch_ref == "" then
		util.Notify(
			"upstream not configured for branch '" .. current_branch .. "'. press 'bu' to set upstream.",
			"warn",
			"oz_git"
		)
		return
	end

	-- extract remote branch name (handle potential errors/empty output)
	local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$") or current_branch -- fallback?

	local branch

	if cur_remote_branch == state.current_branch then
		branch = cur_remote_branch
	else
		branch = cur_remote_branch .. ":" .. current_branch
	end

    -- Magit pull just pulls (with flags). The logic above seems to be constructing specific push/pull specs?
    -- "Git pull <remote> <refspec>"
    s_util.run_n_refresh(("Git pull %s %s"):format(cur_remote, branch))
end

function M.pull_from(flags)
	local args = get_args(flags)
	local remotes = status.state.remotes or { "origin" }
	vim.ui.select(remotes, { prompt = "Pull from:" }, function(choice)
		if choice then
			s_util.run_n_refresh("Git pull" .. args .. " " .. choice)
		end
	end)
end

function M.setup_keymaps(buf, key_grp)
	local pull_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-r", name = "--rebase", type = "switch", desc = "Rebase" },
				{ key = "-a", name = "--autostash", type = "switch", desc = "Autostash" },
			},
		},
		{
			title = "Pull",
			items = {
				{ key = "p", cb = M.pull_cmd, desc = "Pull from upstream" },
				{ key = "u", cb = M.pull_cmd, desc = "Pull from upstream" },
				{ key = "e", cb = M.pull_from, desc = "Pull from..." },
				{
					key = "m",
					cb = function(f)
						local args = get_args(f)
						util.set_cmdline("Git pull" .. args .. " ")
					end,
					desc = "Pull (edit cmd)",
				},
			},
		},
	}

	util.Map("n", "p", function()
		require("oz.util.help_keymaps").show_menu("Pull Actions", pull_opts)
	end, { buffer = buf, desc = "Pull Actions", nowait = true })
end

return M
