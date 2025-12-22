local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local shell = require("oz.util.shell")

local state = status.state

function M.push()
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
		util.set_cmdline("Git push " .. refined_args)
	end
end

function M.pull()
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

	util.set_cmdline(("Git pull %s %s"):format(cur_remote, branch))
end

function M.fetch()
	s_util.run_n_refresh("Git fetch")
end

return M
