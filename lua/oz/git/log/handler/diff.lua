local M = {}
local util = require("oz.util")
local log = require("oz.git.log")

local get_selected_hash = log.get_selected_hash

function M.diff_working()
    local cur_hash = get_selected_hash()
    if #cur_hash > 0 then
        if util.usercmd_exist("DiffviewOpen") then
            vim.cmd("DiffviewOpen " .. cur_hash[1])
        else
            vim.cmd("Git diff " .. cur_hash)
        end
    end
end

function M.diff_commit()
    local cur_hash = get_selected_hash()
    if #cur_hash > 0 then
        if util.usercmd_exist("DiffviewOpen") then
            vim.cmd("DiffviewOpen " .. cur_hash[1] .. "^!")
        else
            vim.cmd("Git show " .. cur_hash[1])
        end
    end
end

local diff_range_hash = {}
function M.diff_range()
    local hashes = get_selected_hash()
    if #hashes > 1 then
        if util.usercmd_exist("DiffviewOpen") then
            vim.cmd("DiffviewOpen " .. hashes[1] .. ".." .. hashes[#hashes])
        else
            vim.cmd("Git diff " .. hashes[1] .. ".." .. hashes[#hashes])
        end
    elseif #hashes == 1 then
        vim.notify_once("press 'dp' on another to pick <end-commit-hash>.")
        util.tbl_insert(diff_range_hash, hashes[1])
        if #diff_range_hash == 2 then
            if util.usercmd_exist("DiffviewOpen") then
                vim.cmd("DiffviewOpen " .. diff_range_hash[1] .. ".." .. diff_range_hash[#diff_range_hash])
            else
                vim.cmd("Git diff " .. diff_range_hash[1] .. ".." .. diff_range_hash[#diff_range_hash])
            end
            diff_range_hash = {}
        end
    end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	util.Map("n", "dv", M.diff_working, { buffer = buf, desc = "diff the working tree against the commit under cursor. <*>" })
	util.Map("n", "dc", M.diff_commit, { buffer = buf, desc = "Diff the changes introduced by commit under cursor. <*>" })
	util.Map({ "n", "x" }, "dp", M.diff_range, { buffer = buf, desc = "Diff commits between a range of commits. <*>" })
    map_help_key("d", "diff[d]")
	key_grp["diff[v]"] = { "dv", "dd", "dc", "dp" }
end

return M
