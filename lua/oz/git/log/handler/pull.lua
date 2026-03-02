local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.pull_cmd(flags)
	local current_branch = util.shellout_str("git branch --show-current")

	if current_branch == "" then
		util.Notify("could not determine current branch.", "error", "oz_git")
		return
	end

	local cur_remote = util.shellout_str(string.format("git config --get branch.%s.remote", current_branch))
	local cur_remote_branch_ref = util.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))

	if cur_remote == "" or cur_remote_branch_ref == "" then
		util.Notify(
			"upstream not configured for branch '" .. current_branch .. "'.",
			"warn",
			"oz_git"
		)
		return
	end

	local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$") or current_branch

	local branch
	if cur_remote_branch == current_branch then
		branch = cur_remote_branch
	else
		branch = cur_remote_branch .. ":" .. current_branch
	end

    log_util.run_n_refresh(("Git pull%s %s %s"):format(get_args(flags), cur_remote, branch))
end

function M.pull_from(flags)
	local args = get_args(flags)
	local remotes = util.shellout_tbl("git remote")
    if #remotes == 0 then
        util.Notify("No remotes found", "warn", "oz_git")
        return
    end

	util.pick(remotes, {
		title = "Pull from",
		on_select = function(choice)
			if choice then
				log_util.run_n_refresh("Git pull" .. args .. " " .. choice)
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	local pull_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-r", name = "--rebase", type = "switch", desc = "Rebase" },
				{ key = "-a", name = "--autostash", type = "switch", desc = "Autostash" },
				{ key = "-f", name = "--ff-only", type = "switch", desc = "Fast-forward only" },
				{ key = "-n", name = "--no-ff", type = "switch", desc = "No fast-forward" },
				{ key = "-q", name = "--quiet", type = "switch", desc = "Quiet" },
			},
		},
		{
			title = "Pull",
			items = {
				{ key = "p", cb = M.pull_cmd, desc = "Pull from upstream" },
				{ key = "u", cb = M.pull_cmd, desc = "Pull from upstream" },
				{ key = "e", cb = M.pull_from, desc = "Pull from..." },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local args = get_args(f)
						util.set_cmdline("Git pull" .. args .. " ")
					end,
					desc = "Pull (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "p", function()
		util.show_menu("Pull Actions", pull_opts)
	end, { buffer = buf, desc = "Pull Actions", nowait = true, silent = true })
end

return M
