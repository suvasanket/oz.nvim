local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local shell = require("oz.util.shell")

function M.create()
    s_util.run_n_refresh("Git commit -q")
end

function M.amend_no_edit()
    s_util.run_n_refresh("Git commit --amend --no-edit -q")
end

function M.amend()
    s_util.run_n_refresh("Git commit --amend -q")
end
function M.undo()
    local ok, commit_ahead = shell.run_command("git rev-list --count @{u}..HEAD")
    local commit_ahead_n = ok and tonumber(commit_ahead[1]) or nil

    if commit_ahead_n == 0 then
        util.Notify("Commit already pushed, you should 'revert'.", "warn", "oz_git")
    else
        s_util.run_n_refresh("Git reset --soft HEAD~1")
    end
end

return M
