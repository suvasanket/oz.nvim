local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local shell = require("oz.util.shell")

local state = status.state

function M.push_cmd(flags)
	local current_branch = s_util.get_branch_under_cursor() or state.current_branch
    local args = ""
    if flags and #flags > 0 then
        args = " " .. table.concat(flags, " ")
    end

	if not current_branch then
		util.Notify("could not determine current branch.", "error", "oz_git")
		return
	end

    -- Logic simplified for menu action 'p' (PushCurrent)
	local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", current_branch))
    -- If no upstream, maybe prompt? Or let git handle it.
    -- Magit 'p' usually pushes to configured upstream or prompts.
    
    if cur_remote == "" then
         -- No upstream
         util.Notify("No upstream configured. Use 'u' to push to specific upstream or configure it.", "warn", "oz_git")
         return
    end
    
    s_util.run_n_refresh("Git push" .. args)
end

function M.push_upstream(flags)
    -- Push to upstream (explicitly -u if needed or just push)
    -- Magit 'u' is Push to upstream.
    M.push_cmd(flags)
end

function M.pull_cmd(flags)
    local args = ""
    if flags and #flags > 0 then
        args = " " .. table.concat(flags, " ")
    end
	s_util.run_n_refresh("Git pull" .. args)
end

function M.fetch_cmd(flags)
    local args = ""
    if flags and #flags > 0 then
        args = " " .. table.concat(flags, " ")
    end
	s_util.run_n_refresh("Git fetch" .. args)
end

function M.setup_keymaps(buf, key_grp)
    -- Push Menu
    local push_opts = {
        {
            title = "Switches",
            items = {
                { key = "-f", name = "--force-with-lease", type = "switch", desc = "Force with lease" },
                { key = "-F", name = "--force", type = "switch", desc = "Force" },
                { key = "-u", name = "--set-upstream", type = "switch", desc = "Set upstream" },
                { key = "-n", name = "--no-verify", type = "switch", desc = "No verify" },
            }
        },
        {
            title = "Push",
            items = {
                { key = "p", cb = M.push_cmd, desc = "Push to upstream" },
                { key = "e", cb = function(f) 
                    local flags = f and table.concat(f, " ") or ""
                    util.set_cmdline("Git push " .. flags .. " ") 
                end, desc = "Push elsewhere" },
            }
        }
    }
    
    -- Pull Menu
    local pull_opts = {
        {
            title = "Switches",
            items = {
                { key = "-r", name = "--rebase", type = "switch", desc = "Rebase" },
            }
        },
        {
            title = "Pull",
            items = {
                { key = "p", cb = M.pull_cmd, desc = "Pull from upstream" },
                { key = "e", cb = function(f)
                    local flags = f and table.concat(f, " ") or ""
                    util.set_cmdline("Git pull " .. flags .. " ")
                end, desc = "Pull elsewhere" },
            }
        }
    }

    -- Fetch Menu
    local fetch_opts = {
        {
            title = "Switches",
            items = {
                { key = "-p", name = "--prune", type = "switch", desc = "Prune" },
                { key = "-t", name = "--tags", type = "switch", desc = "Tags" },
            }
        },
        {
            title = "Fetch",
            items = {
                { key = "p", cb = M.fetch_cmd, desc = "Fetch upstream" },
                { key = "a", cb = function(f)
                    local flags = f and table.concat(f, " ") or ""
                    s_util.run_n_refresh("Git fetch --all " .. flags)
                end, desc = "Fetch all" },
                { key = "e", cb = function(f)
                    local flags = f and table.concat(f, " ") or ""
                    util.set_cmdline("Git fetch " .. flags .. " ")
                end, desc = "Fetch elsewhere" },
            }
        }
    }

	util.Map("n", "P", function()
		require("oz.util.help_keymaps").show_menu("Push", push_opts)
	end, { buffer = buf, desc = "Push Actions", nowait = true })
    
	util.Map("n", "p", function()
		require("oz.util.help_keymaps").show_menu("Pull", pull_opts)
	end, { buffer = buf, desc = "Pull Actions", nowait = true })
    
	util.Map("n", "f", function()
		require("oz.util.help_keymaps").show_menu("Fetch", fetch_opts)
	end, { buffer = buf, desc = "Fetch Actions", nowait = true })
    
	key_grp["remote action"] = { "p", "P", "f" }
end

return M
