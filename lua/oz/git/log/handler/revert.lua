local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local grab_hashs = log.grab_hashs
local run_n_refresh = log_util.run_n_refresh
local clear_all_picked = log_util.clear_all_picked

function M.handle_revert()
	local str
	if #grab_hashs > 0 then
		str = table.concat(grab_hashs, " ")
		clear_all_picked()
	else
		local commits = get_selected_hash()
		if #commits == 1 then
			str = commits[1]
		elseif #commits == 2 then
			str = ("%s %s"):format(commits[1], commits[2])
		elseif #commits > 2 then
			str = ("%s..%s"):format(commits[1], commits[#commits])
		end
	end
	if str then
		util.set_cmdline("Git revert| " .. str)
	end
end

function M.edit()
    local hash = get_selected_hash()
    if #hash == 1 then
        run_n_refresh("Git revert --edit " .. hash[1])
    end
end

function M.no_edit()
    local hash = get_selected_hash()
    if #hash == 1 then
        run_n_refresh("Git revert --no-edit " .. hash[1])
    end
end

function M.continue()
    run_n_refresh("Git revert --continue")
end

function M.skip()
    run_n_refresh("Git revert --skip")
end

function M.quit()
    run_n_refresh("Git revert --quit")
end

function M.abort()
    run_n_refresh("Git revert --abort")
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	util.Map({ "n", "x" }, "uu", M.handle_revert, { buffer = buf, desc = "Revert selection or current commit. <*>" })
	util.Map("n", "ui", M.edit, { buffer = buf, desc = "Revert commit with edit. <*>" })
	util.Map("n", "ue", M.no_edit, { buffer = buf, desc = "Revert commit with no-edit. <*>" })
	util.Map("n", "ul", M.continue, { buffer = buf, desc = "Revert continue." })
	util.Map("n", "uk", M.skip, { buffer = buf, desc = "Revert skip." })
	util.Map("n", "uq", M.quit, { buffer = buf, desc = "Revert quit." })
	util.Map("n", "ua", M.abort, { buffer = buf, desc = "Revert abort." })
	map_help_key("u", "revert")
	key_grp["revert[u]"] = { "uu", "ul", "uk", "ua", "uq", "ui", "ue" }
end

return M
