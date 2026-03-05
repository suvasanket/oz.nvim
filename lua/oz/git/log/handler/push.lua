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

local function get_push_args(source_ref)
	local current_branch = util.shellout_str("git branch --show-current")

	if current_branch == "" then
		util.Notify("could not determine current branch.", "error", "oz_git")
		return nil
	end

	local cur_remote = util.shellout_str(string.format("git config --get branch.%s.remote", current_branch))
	local cur_remote_branch_ref = util.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))

	local refined_args
	if cur_remote_branch_ref ~= "" then
		local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$") or current_branch
		local branch_spec
		if source_ref then
			branch_spec = source_ref .. ":" .. cur_remote_branch
		elseif cur_remote_branch == current_branch then
			branch_spec = cur_remote_branch
		else
			branch_spec = current_branch .. ":" .. cur_remote_branch
		end
		refined_args = string.format("%s %s", cur_remote, branch_spec)
	else
		local remote = util.shellout_str("git remote")
		if remote ~= "" then
			local r = remote:match("%S+")
			if source_ref then
				refined_args = string.format("%s %s:%s", r, source_ref, current_branch)
			else
				refined_args = ("-u %s %s"):format(r, current_branch)
			end
		else
			util.Notify("Add a remote first", "warn", "oz_git")
			return nil
		end
	end

	return refined_args
end

function M.push_cmd(flags)
	local refined_args = get_push_args()
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

	local function pick_branch(remote)
		if not remote then
			return
		end

		local branches = util.shellout_tbl({
			"git",
			"for-each-ref",
			"--format=%(refname:short)",
			"refs/remotes/" .. remote,
		})
		for i, branch in ipairs(branches) do
			-- Remove any literal quotes and the remote prefix
			branches[i] = branch:gsub("^" .. remote .. "/", ""):gsub("['\"]", "")
		end
		branches = vim.tbl_filter(function(b)
			return b ~= "HEAD" and b ~= ""
		end, branches)

		-- Also add local branches that might want to be pushed
		local local_branches = util.shellout_tbl({
			"git",
			"for-each-ref",
			"--format=%(refname:short)",
			"refs/heads",
		})
		for _, b in ipairs(local_branches) do
			local clean_b = b:gsub("['\"]", "")
			if clean_b ~= "" and not vim.tbl_contains(branches, clean_b) then
				table.insert(branches, clean_b)
			end
		end

		if #branches == 0 then
			log_util.run_n_refresh("Git push" .. args .. " " .. remote)
			return
		end

		util.pick(branches, {
			title = "Push branch to " .. remote,
			on_select = function(branch)
				if branch then
					log_util.run_n_refresh(string.format("Git push%s %s %s", args, remote, branch))
				end
			end,
		})
	end

	if #remotes == 1 then
		pick_branch(remotes[1])
	else
		util.pick(remotes, {
			title = "Push to remote",
			on_select = pick_branch,
		})
	end
end

function M.push_sha(flags)
	local hashes = log_util.get_selected_hash()
	if not hashes or #hashes == 0 then
		util.Notify("No SHA found under cursor", "warn", "oz_git")
		return
	end
	local sha = hashes[1]

	local refined_args = get_push_args(sha)
	if refined_args then
		local cmd = string.format("Git push %s%s", refined_args, get_args(flags))
		log_util.run_n_refresh(cmd)
	end
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
                { key = "P", cb = M.push_sha, desc = "Push commit under cursor" },
				{ key = "h", cb = M.push_cmd, desc = "Push HEAD to upstream" },
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
