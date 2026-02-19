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

function M.push_cmd(flags)
	local current_branch = s_util.get_branch_under_cursor() or state.current_branch

	if not current_branch then
		util.Notify("could not determine current branch.", "error", "oz_git")
		return
	end

	local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", current_branch))
	local cur_remote_branch_ref = shell.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))
	local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$") or current_branch -- fallback?

	local refined_args, branch
	if cur_remote_branch == state.current_branch then
		branch = cur_remote_branch
	else
		branch = current_branch .. ":" .. cur_remote_branch
	end

	if cur_remote_branch_ref == "" then
		local remote = shell.shellout_str("git remote")
		if remote ~= "" then
			refined_args = ("-u %s %s"):format(remote, current_branch)
		else
			util.Notify("press 'ma' to add a remote first", "warn", "oz_git")
		end
	else
		refined_args = string.format("%s %s", cur_remote, branch)
	end

	if refined_args then
		local cmd = string.format("Git push %s%s", refined_args, get_args(flags))
		s_util.run_n_refresh(cmd)
	end
end

function M.push_to(flags)
	local args = get_args(flags)
	local remotes = status.state.remotes or { "origin" } -- Simplified

	vim.ui.select(remotes, { prompt = "Push to:" }, function(choice)
		if choice then
			s_util.run_n_refresh("Git push" .. args .. " " .. choice)
		end
	end)
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
			},
		},
		{
			title = "Push",
			items = {
				{ key = "P", cb = M.push_cmd, desc = "Push current to upstream" },
				{ key = "u", cb = M.push_cmd, desc = "Push current to upstream" },
				{ key = "e", cb = M.push_to, desc = "Push to..." },
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
