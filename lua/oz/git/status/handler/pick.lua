local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local s_util = require("oz.git.status.util")

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
            util.setup_hls({ "OzActive" })
			vim.api.nvim_echo({ { ":Git | " }, { table.concat(status_grab_buffer, " "), "OzActive" } }, false, {})
		elseif status_grab_buffer[1] == entry then
			-- Last item, clear and stop monitoring
            util.stop_monitoring(status_grab_buffer)
			status_grab_buffer = {} -- Reassign to new empty table
			status.status_grab_buffer = status_grab_buffer -- Update original reference if needed
			vim.api.nvim_echo({ { "" } }, false, {})
		end
	else
		-- Pick
		util.tbl_insert(status_grab_buffer, entry) -- Add to existing table

		-- Start monitoring if it's the first item picked
		if #status_grab_buffer == 1 then
            util.start_monitoring(status_grab_buffer, {
				interval = 2000,
				buf = buf_id, -- Use captured buf_id
				on_active = function(t)
                    util.setup_hls({ "OzActive" })
					vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "OzActive" } }, false, {})
				end,
			})
		else
			-- Already monitoring, just update echo if needed
            util.setup_hls({ "OzActive" })
			vim.api.nvim_echo({ { ":Git | " }, { table.concat(status_grab_buffer, " "), "OzActive" } }, false, {})
		end
	end
end

function M.edit_picked()
	if #status_grab_buffer > 0 then
        util.stop_monitoring(status_grab_buffer)
		util.set_cmdline("Git | " .. table.concat(status_grab_buffer, " "))
		status_grab_buffer = {} -- Clear after editing
		status.status_grab_buffer = status_grab_buffer -- Update original reference
	end
end

function M.discard_picked()
	if #status_grab_buffer > 0 then
        util.stop_monitoring(status_grab_buffer)
		status_grab_buffer = {} -- Clear the buffer
		status.status_grab_buffer = status_grab_buffer -- Update original reference
		vim.api.nvim_echo({ { "" } }, false, {}) -- Clear echo area
	end
end

function M.setup_keymaps(buf, key_grp)
	buf_id = buf
	local user_mappings = require("oz.git").user_config.mappings -- Ensure this is available
	vim.keymap.set(
		"n",
		user_mappings.toggle_pick,
		M.toggle_pick,
		{ nowait = true, buffer = buf, desc = "Pick/unpick file/branch/stash.", silent = true }
	)
	util.Map("n", { "a", "i" }, M.edit_picked, { nowait = true, buffer = buf, desc = "Enter cmdline to edit picked." })
	vim.keymap.set(
		"n",
		user_mappings.unpick_all,
		M.discard_picked,
		{ nowait = true, buffer = buf, desc = "Discard picked entries.", silent = true }
	)
	key_grp["Pick"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" }
end

return M
