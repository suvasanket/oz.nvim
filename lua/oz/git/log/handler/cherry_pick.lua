local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")

local get_selected_hash = log.get_selected_hash
local grab_hashs = log.grab_hashs
local run_n_refresh = log_util.run_n_refresh
local clear_all_picked = log_util.clear_all_picked

function M.handle_cherrypick()
	local input
	if #grab_hashs > 0 then
		input = " " .. table.concat(grab_hashs, " ")
		clear_all_picked()
	else
		local hash = get_selected_hash()
		if #hash == 1 then
			input = util.inactive_input(":Git cherry-pick", " -x " .. hash[1])
		elseif #hash == 2 then
			input = util.inactive_input(":Git cherry-pick", " -x " .. table.concat(hash, " "))
		elseif #hash > 2 then
			input = util.inactive_input(":Git cherry-pick", " -x " .. hash[1] .. ".." .. hash[#hash])
		end
	end
	if input then
		run_n_refresh("Git cherry-pick" .. input)
	end
end

function M.abort()
    run_n_refresh("Git cherry-pick --abort")
end

function M.quit()
    run_n_refresh("Git cherry-pick --quit")
end

function M.continue()
    run_n_refresh("Git cherry-pick --continue")
end

function M.skip()
    run_n_refresh("Git cherry-pick --skip")
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	util.Map({ "n", "x" }, "pp", M.handle_cherrypick, { buffer = buf, desc = "Cherry-pick commit under cursor. <*>" })

	util.Map("n", "pa", M.abort, { buffer = buf, desc = "Cherry-pick abort." })
	util.Map("n", "pq", M.quit, { buffer = buf, desc = "Cherry-pick quit." })
	util.Map("n", "pl", M.continue, { buffer = buf, desc = "Cherry-pick continue." })
	util.Map("n", "pk", M.skip, { buffer = buf, desc = "Cherry-pick skip." })
	map_help_key("p", "cherry-pick")
	key_grp["cherry-pick[p]"] = { "pp", "pa", "pk", "pl", "pq" }
end

return M
