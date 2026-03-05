local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.fetch_cmd(flags)
	local args = get_args(flags)
	s_util.run_n_refresh("Git fetch" .. args)
end

function M.fetch_from(flags)
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
			-- Remove any literal quotes that might have slipped in and the remote prefix
			branches[i] = branch:gsub("^" .. remote .. "/", ""):gsub("['\"]", "")
		end
		branches = vim.tbl_filter(function(b)
			return b ~= "HEAD" and b ~= ""
		end, branches)

		if #branches == 0 then
			s_util.run_n_refresh("Git fetch" .. args .. " " .. remote)
			return
		end

		util.pick(branches, {
			title = "Fetch branch from " .. remote,
			on_select = function(branch)
				if branch then
					s_util.run_n_refresh(string.format("Git fetch%s %s %s", args, remote, branch))
				end
			end,
		})
	end

	if #remotes == 1 then
		pick_branch(remotes[1])
	else
		util.pick(remotes, {
			title = "Fetch from remote",
			on_select = pick_branch,
		})
	end
end

function M.setup_keymaps(buf, key_grp)
	local fetch_opts = {
		{
			title = "Switches",
			items = {
				{ key = "-p", name = "--prune", type = "switch", desc = "Prune" },
				{ key = "-t", name = "--tags", type = "switch", desc = "Tags" },
				{ key = "-f", name = "--force", type = "switch", desc = "Force" },
				{ key = "-q", name = "--quiet", type = "switch", desc = "Quiet" },
			},
		},
		{
			title = "Fetch",
			items = {
				{ key = "f", cb = M.fetch_cmd, desc = "Fetch upstream" },
				{
					key = "a",
					cb = function(f)
						s_util.run_n_refresh("Git fetch --all" .. get_args(f))
					end,
					desc = "Fetch all",
				},
				{ key = "e", cb = M.fetch_from, desc = "Fetch from..." },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local args = get_args(f)
						util.set_cmdline("Git fetch" .. args .. " ")
					end,
					desc = "Fetch elsewhere",
				},
			},
		},
	}

	vim.keymap.set("n", "f", function()
		util.show_menu("Fetch Actions", fetch_opts)
	end, { buffer = buf, desc = "Fetch Actions", nowait = true, silent = true })
end

return M
