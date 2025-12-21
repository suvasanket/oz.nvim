local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")

local status_grab_buffer = status.status_grab_buffer
local buf_id = nil

function M.toggle_pick()
    local line_content = vim.api.nvim_get_current_line()
    local entry = line_content:match("^%s*(stash@{%d+})") -- Check for stash first
    if not entry then
        entry = s_util.get_branch_under_cursor() or s_util.get_file_under_cursor(true)[1]
    end

    if not entry then
        util.Notify("Can only pick files, branches, or stashes.", "error", "oz_git")
        return
    end

    -- Logic for picking/unpicking
    if vim.tbl_contains(status_grab_buffer, entry) then
        -- Unpick
        if #status_grab_buffer > 1 then
            util.remove_from_tbl(status_grab_buffer, entry)
            vim.api.nvim_echo({ { ":Git | " }, { table.concat(status_grab_buffer, " "), "@attribute" } }, false, {})
        elseif status_grab_buffer[1] == entry then
            -- Last item, clear and stop monitoring
            util.tbl_monitor().stop_monitoring(status_grab_buffer)
            status_grab_buffer = {} -- Reassign to new empty table
            status.status_grab_buffer = status_grab_buffer -- Update original reference if needed
            vim.api.nvim_echo({ { "" } }, false, {})
        end
    else
        -- Pick
        util.tbl_insert(status_grab_buffer, entry) -- Add to existing table

        -- Start monitoring if it's the first item picked
        if #status_grab_buffer == 1 then
            util.tbl_monitor().start_monitoring(status_grab_buffer, {
                interval = 2000,
                buf = buf_id, -- Use captured buf_id
                on_active = function(t)
                    vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
                end,
            })
        else
            -- Already monitoring, just update echo if needed
            vim.api.nvim_echo({ { ":Git | " }, { table.concat(status_grab_buffer, " "), "@attribute" } }, false, {})
        end
    end
end

function M.edit_picked()
    if #status_grab_buffer > 0 then
        util.tbl_monitor().stop_monitoring(status_grab_buffer)
        g_util.set_cmdline("Git | " .. table.concat(status_grab_buffer, " "))
        status_grab_buffer = {} -- Clear after editing
        status.status_grab_buffer = status_grab_buffer -- Update original reference
    end
end

function M.discard_picked()
    if #status_grab_buffer > 0 then
        util.tbl_monitor().stop_monitoring(status_grab_buffer)
        status_grab_buffer = {} -- Clear the buffer
        status.status_grab_buffer = status_grab_buffer -- Update original reference
        vim.api.nvim_echo({ { "" } }, false, {}) -- Clear echo area
    end
end

return M
