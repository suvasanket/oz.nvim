local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local status = require("oz.git.status")
local shell = require("oz.util.shell")

function M.new()
    local b_name = util.inactive_input(":Git branch ")
    if b_name and vim.trim(b_name) ~= "" then
        s_util.run_n_refresh("Git branch " .. b_name)
    elseif b_name == "" then
        util.Notify("Branch name cannot be empty.", "warn", "oz_git")
    end
end

function M.delete()
    local branch = s_util.get_branch_under_cursor()
    if branch then
        if branch == status.state.current_branch then
            util.Notify("Cannot delete the current branch.", "error", "oz_git")
            return
        end
        local ans = util.prompt("Delete branch '" .. branch .. "'?", "&Local\n&Remote\n&Both\n&Nevermind", 4)
        if ans == 1 then
            s_util.run_n_refresh("Git branch -d " .. branch)
        elseif ans == 2 then
            local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", branch))
            s_util.run_n_refresh(("Git push %s --delete %s"):format(cur_remote, branch))
        elseif ans == 3 then
            s_util.run_n_refresh("Git branch -d " .. branch)
            local cur_remote = shell.shellout_str(string.format("git config --get branch.%s.remote", branch))
            s_util.run_n_refresh(("Git push %s --delete %s"):format(cur_remote, branch))
        end
    else
        util.Notify("Cursor not on a deletable branch.", "warn", "oz_git")
    end
end

function M.set_upstream()
    local branch = s_util.get_branch_under_cursor()
    if not branch then
        util.Notify("Cursor not on a local branch.", "warn", "oz_git")
        return
    end

    local remote_branches_raw = shell.shellout_tbl("git branch -r")
    local remote_branches = {}
    for _, rb in ipairs(remote_branches_raw) do
        local trimmed_rb = vim.trim(rb)
        -- Filter out 'HEAD ->' entries if they appear
        if not trimmed_rb:match("^HEAD ") then
            table.insert(remote_branches, trimmed_rb)
        end
    end

    if #remote_branches == 0 then
        util.Notify("No remote branches found.", "info", "oz_git")
        return
    end

    vim.ui.select(remote_branches, { prompt = "Select upstream branch for '" .. branch .. "':" }, function(choice)
        if choice then
            s_util.run_n_refresh("Git branch --set-upstream-to=" .. choice .. " " .. branch)
        end
    end)
end

function M.unset_upstream()
    local branch = s_util.get_branch_under_cursor()
    if branch then
        local upstream = shell.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", branch))
        if upstream == "" then
            util.Notify("Branch '" .. branch .. "' has no upstream configured.", "info", "oz_git")
            return
        end
        local ans = util.prompt("Unset upstream ('" .. upstream .. "') for branch '" .. branch .. "'?", "&Yes\n&No", 2)
        if ans == 1 then
            s_util.run_n_refresh("Git branch --unset-upstream " .. branch)
        end
    else
        util.Notify("Cursor not on a local branch.", "warn", "oz_git")
    end
end

return M
