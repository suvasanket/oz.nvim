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

function M.push_cmd(flags)
	local current_branch = util.shellout_str("git branch --show-current")

	if current_branch == "" then
		util.Notify("could not determine current branch.", "error", "oz_git")
		return
	end

	local cur_remote = util.shellout_str(string.format("git config --get branch.%s.remote", current_branch))
	local cur_remote_branch_ref = util.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))

	local refined_args, branch
	if cur_remote_branch_ref ~= "" then
        local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$") or current_branch
        if cur_remote_branch == current_branch then
            branch = cur_remote_branch
        else
            branch = current_branch .. ":" .. cur_remote_branch
        end
		refined_args = string.format("%s %s", cur_remote, branch)
	else
		local remote = util.shellout_str("git remote")
		if remote ~= "" then
			refined_args = ("-u %s %s"):format(remote:match("%S+"), current_branch)
		else
			util.Notify("Add a remote first", "warn", "oz_git")
            return
		end
	end

	if refined_args then
		local cmd = string.format("Git push %s%s", refined_args, get_args(flags))
		log_util.run_n_refresh(cmd)
	end
end

function M.push_to(flags)
	local args = get_args(flags)
	local remotes = util.shellout_tbl("git remote")
    if #remotes == 0 then
        util.Notify("No remotes found", "warn", "oz_git")
        return
    end

	util.pick(remotes, {
		title = "Push to",
		on_select = function(choice)
			if choice then
				log_util.run_n_refresh("Git push" .. args .. " " .. choice)
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	-- Push Menu (P)
	local push_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-f", name = "--force-with-lease", type = "switch", desc = "Force with lease" },
				{ key = "-F", name = "--force", type = "switch", desc = "Force" },
				{ key = "-u", name = "--set-upstream", type = "switch", desc = "Set upstream" },
				{ key = "-n", name = "--no-verify", type = "switch", desc = "No verify" },
				{ key = "-d", name = "--dry-run", type = "switch", desc = "Dry run" },
				{ key = "-t", name = "--tags", type = "switch", desc = "Tags" },
				{ key = "-q", name = "--quiet", type = "switch", desc = "Quiet" },
			},
		},
		{
			title = "Push",
			items = {
				{ key = "P", cb = M.push_cmd, desc = "Push to upstream" },
				{ key = "u", cb = M.push_cmd, desc = "Push to upstream" },
				{ key = "e", cb = M.push_to, desc = "Push to..." },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local args = get_args(f)
						util.set_cmdline("Git push" .. args .. " ")
					end,
					desc = "Push (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "P", function()
		util.show_menu("Push Actions", push_opts)
	end, { buffer = buf, desc = "Push Actions", nowait = true, silent = true })
end

return M
