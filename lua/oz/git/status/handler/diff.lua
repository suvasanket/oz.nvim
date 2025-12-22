local M = {}

local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local git = require("oz.git")
local shell = require("oz.util.shell")

local state = status.state
local get_shellout = shell.run_command

function M.file_history()
    local cur_file = s_util.get_file_under_cursor()
    local stash = s_util.get_stash_under_cursor()
    if #cur_file > 0 then
        if util.usercmd_exist("DiffviewFileHistory") then
            vim.cmd("DiffviewFileHistory " .. cur_file[1])
        else
            vim.cmd(("Git difftool -y HEAD -- %s"):format(cur_file[1]))
            vim.fn.timer_start(700, function()
                git.cleanup_git_jobs({ cmd = "difftool" })
            end)
        end
    elseif #stash > 0 then
        if util.usercmd_exist("DiffviewFileHistory") then
            vim.cmd(("DiffviewFileHistory -g --range=stash@{%s}"):format(tostring(stash.index)))
        else
            util.Notify("following operation require diffview.nvim", "error", "oz_git")
        end
    end
end

function M.file_changes()
    local cur_file = s_util.get_file_under_cursor()
    if #cur_file > 0 then
        if util.usercmd_exist("DiffviewOpen") then
            vim.cmd("DiffviewOpen --selected-file=" .. cur_file[1])
            vim.schedule(function()
                vim.cmd("DiffviewToggleFiles")
            end)
        else
            vim.cmd(("Git difftool -y HEAD -- %s"):format(cur_file[1]))
            vim.fn.timer_start(700, function()
                git.cleanup_git_jobs({ cmd = "difftool" })
            end)
        end
    else
        if util.usercmd_exist("DiffviewOpen") then
            vim.cmd("DiffviewOpen -uno")
        else
            --FIXME: add check if tabclosed then auto remove its buffers then it will continue otherwise remains in bg.
            vim.cmd("Git difftool -y --cached")
        end
    end
end

function M.remote()
    local current_branch = s_util.get_branch_under_cursor() or state.current_branch

    local ok, cur_remote_branch_ref = get_shellout(string.format("git rev-parse --abbrev-ref %s@{u}", current_branch))
    if ok then
        vim.cmd(("DiffviewOpen %s...%s"):format(cur_remote_branch_ref[1], current_branch))
    end
end

function M.branch()
    local branch_under_cursor = s_util.get_branch_under_cursor()
    if branch_under_cursor then
        util.set_cmdline(("DiffviewOpen %s|...%s"):format(state.current_branch, branch_under_cursor))
    else
        util.set_cmdline(("DiffviewOpen %s|"):format(state.current_branch))
    end
end

return M
