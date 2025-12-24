local M = {}
local util = require("oz.util")
local status = require("oz.git.status")
local s_util = require("oz.git.status.util")
local git = require("oz.git")
local wizard = require("oz.git.wizard")
local caching = require("oz.caching")

local refresh = status.refresh_buf

local open_in_ozgitwin = require("oz.git.oz_git_win").open_oz_git_win

function M.quit()
    vim.api.nvim_echo({ { "" } }, false, {})
    vim.cmd("close")
end

function M.tab()
    if s_util.toggle_section() then
        return
    end
end


function M.rename()
    local branch = s_util.get_branch_under_cursor()
    local file = s_util.get_file_under_cursor(true)[1]

    if file or branch then
        git.after_exec_complete(function(code)
            if code == 0 then
                refresh()
            end
        end, true)
    end

    if file then
        local new_name = util.UserInput("New name: ", file)
        if new_name then
            s_util.run_n_refresh("Git mv " .. file .. " " .. new_name)
        end
    elseif branch then
        local new_name = util.UserInput("New name: ", branch)
        if new_name then
            s_util.run_n_refresh("Git branch -m " .. branch .. " " .. new_name)
        end
    end
end

function M.stash_apply()
    local current_line = vim.api.nvim_get_current_line()
    local stash = current_line:match("^%s*(stash@{%d+})")
    if stash then
        s_util.run_n_refresh("G stash apply -q " .. stash)
    end
end

function M.stash_pop()
    local current_line = vim.api.nvim_get_current_line()
    local stash = current_line:match("^%s*(stash@{%d+})")
    if stash then
        s_util.run_n_refresh("G stash pop -q " .. stash)
    end
end

function M.stash_drop()
    local current_line = vim.api.nvim_get_current_line()
    local stash = current_line:match("^%s*(stash@{%d+})")
    if stash then
        s_util.run_n_refresh("G stash drop -q " .. stash)
    end
end

-- helper: handle enter
function M.enter_key_helper(line)
    if line:match('"([^"]+)"') then -- populate cmdline with help.
        local quoted_str = line:match('"([^"]+)"'):gsub("git", "Git"):gsub("<[^>]*>", "")
        util.set_cmdline(quoted_str)
    elseif line:match("Stash list:") then -- stash detail
        git.after_exec_complete(function(_, out, _)
            open_in_ozgitwin(out, nil)
        end, true)
        vim.cmd("Git stash list --stat")
    elseif line:match("^On branch") then -- branch detail
        vim.cmd("Git show-branch -a")
    elseif line:match("^HEAD detached at") then -- detached head
        util.set_cmdline("Git checkout ")
    end
end

function M.enter_key()
    local file = s_util.get_file_under_cursor()
    local branch = s_util.get_branch_under_cursor()
    local stash = s_util.get_stash_under_cursor()

    if #file > 0 and (vim.fn.filereadable(file[1]) == 1 or vim.fn.isdirectory(file[1]) == 1) then -- if file.
        vim.cmd("wincmd k | edit " .. file[1])
    elseif branch then -- if branch
        git.after_exec_complete(function(code, _, err)
            if code == 0 then
                refresh()
                vim.cmd("checktime")
            else
                open_in_ozgitwin(err, nil)
            end
        end, true)
        vim.cmd("Git checkout " .. branch)
    elseif #stash ~= 0 then -- if stash
        git.after_exec_complete(function(_, out, _)
            open_in_ozgitwin(out, nil)
        end, true)
        vim.cmd(("Git stash show stash@{%s}"):format(stash.index))
    else -- fallback with current line content action.
        M.enter_key_helper(vim.api.nvim_get_current_line())
    end
end

function M.goto_log()
    vim.cmd("close") -- Close status window before opening log
    require("oz.git.log").commit_log({ level = 1, from = "Git" })
end

function M.goto_log_context()
    local branch = s_util.get_branch_under_cursor()
    local file = s_util.get_file_under_cursor(true)
    vim.cmd("close")
    if branch then
        require("oz.git.log").commit_log({ level = 1, from = "Git" }, { branch })
    elseif #file > 0 then
        --FIXME file log not working
        require("oz.git.log").commit_log({ level = 1, from = "Git" }, { "--", unpack(file) })
    else
        require("oz.git.log").commit_log({ level = 1, from = "Git" })
    end
end

function M.goto_gitignore()
    local path = s_util.get_file_under_cursor(true)
    if #path > 0 then
        require("oz.git.status.add_to_ignore").add_to_gitignore(path)
    end
end


function M.conflict_start_manual()
    vim.cmd("close") -- Close status window
    wizard.start_conflict_resolution()
    vim.notify_once(
        "]x / [x => jump between conflict marker.\n:CompleteConflictResolution => complete",
        vim.log.levels.INFO,
        { title = "oz_git", timeout = 4000 }
    )

    -- Define command for completion within the resolution context
    vim.api.nvim_create_user_command("CompleteConflictResolution", function()
        wizard.complete_conflict_resolution()
        vim.api.nvim_del_user_command("CompleteConflictResolution") -- Clean up command
    end, {})
end

function M.conflict_complete()
    if wizard.on_conflict_resolution then
        wizard.complete_conflict_resolution()
        -- Maybe refresh status after completion? Or rely on wizard to handle it.
    else
        util.Notify("Start the resolution with 'xo' first.", "warn", "oz_git")
    end
end

function M.conflict_diffview()
    if util.usercmd_exist("DiffviewOpen") then
        vim.cmd("DiffviewOpen")
    else
        util.Notify("DiffviewOpen command not found.", "error", "oz_git")
    end
end

function M.merge_branch(flag)
    local branch_under_cursor = s_util.get_branch_under_cursor()
    local key, json, input = "git_user_merge_flags", "oz_git", nil
    flag = not flag and caching.get_data(key, json) or flag

    if branch_under_cursor then
        if flag then
            input = util.inactive_input(":Git merge", " " .. flag .. " " .. branch_under_cursor)
        else
            input = util.inactive_input(":Git merge", " " .. branch_under_cursor)
        end
        if input then
            s_util.run_n_refresh("Git merge" .. input)
            local flags_to_cache = util.extract_flags(input)
            caching.set_data(key, table.concat(flags_to_cache, " "), json)
        end
    end
end

function M.rebase_branch()
    local branch_under_cursor = s_util.get_branch_under_cursor()
    if branch_under_cursor then
        util.set_cmdline("Git rebase| " .. branch_under_cursor)
    end
end

function M.reset(arg)
    local files = s_util.get_file_under_cursor(true)
    local branch = s_util.get_branch_under_cursor()
    local args = arg .. " HEAD~1"
    if #files > 0 then
        if arg then
            args = ("%s %s"):format(arg, table.concat(files, " "))
        else
            args = table.concat(files, " ")
        end
    elseif branch then
        if arg then
            args = ("%s %s"):format(arg, branch)
        else
            args = branch
        end
    end
    util.set_cmdline(("Git reset %s"):format(args or arg))
end

function M.undo_orig_head()
    s_util.run_n_refresh("Git reset ORIG_HEAD")
end

return M
