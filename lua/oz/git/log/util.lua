local M = {}
local util = require("oz.util")
local git = require("oz.git")
local log = require("oz.git.log")

-- Run git command and refresh log buffer
function M.run_n_refresh(cmd)
	git.after_exec_complete(function()
		vim.schedule(function()
			log.refresh_buf(true)
		end)
	end)
	vim.api.nvim_set_hl(0, "ozInactivePrompt", { fg = "#757575" })
	vim.api.nvim_echo({ { ":" .. cmd, "ozInactivePrompt" } }, false, {})
	vim.cmd(cmd)
end

-- Clear all picked hashes
function M.clear_all_picked()
	local grab_hashs = log.grab_hashs
	util.tbl_monitor().stop_monitoring(grab_hashs)

	-- Clear the table in-place
	for k in pairs(grab_hashs) do grab_hashs[k] = nil end
    while #grab_hashs > 0 do table.remove(grab_hashs) end

	vim.api.nvim_echo({ { "" } }, false, {})
end

-- Execute callback with current commit hash
function M.cmd_upon_current_commit(callback)
	local hash = log.get_selected_hash()
	if #hash > 0 then
		callback(hash[1])
	end
end

return M
