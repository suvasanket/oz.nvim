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
	local args = get_args(flags)

	if not current_branch then
		util.Notify("could not determine current branch.", "error", "oz_git")
		return
	end

	local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", current_branch))

	if cur_remote == "" then
		-- Try to find origin or prompt
		if #flags == 0 then
			-- No flags, basic push, might fail if no upstream
			-- Magit prompts.
			util.set_cmdline("Git push -u origin " .. current_branch)
			return
		end
	end

	s_util.run_n_refresh("Git push" .. args)
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
			},
		},
		{
			title = "Push",
			items = {
				{ key = "P", cb = M.push_cmd, desc = "Push current to upstream" },
				{ key = "u", cb = M.push_cmd, desc = "Push current to upstream" },
				{ key = "e", cb = M.push_to, desc = "Push to..." },
				{
					key = "m",
					cb = function(f)
						local args = get_args(f)
						util.set_cmdline("Git push" .. args .. " ")
					end,
					desc = "Push (edit cmd)",
				},
			},
		},
	}

	util.Map("n", "P", function()
		require("oz.util.help_keymaps").show_menu("Push Actions", push_opts)
	end, { buffer = buf, desc = "Push Actions", nowait = true })
end

return M
