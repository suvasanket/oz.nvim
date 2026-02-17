local M = {}
local util = require("oz.util")

-- make err win buffer mappings
local function make_err_buf_mappings(buf_id, cmd, dir)
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf_id, desc = "Close", silent = true })
	vim.keymap.set("n", "t", function()
		require("oz.term").run_in_term(cmd, dir)
	end, { buffer = buf_id, desc = "Run in term", silent = true })
	vim.keymap.set("n", "A", function()
		local cache = require("oz.caching")
		local res = util.prompt("EFM scope", "&Filetype specific\n&Project specific", 1)
		if not res or res == 0 then
			return
		end

		local efm_str = util.UserInput("EFM:")
		if not efm_str or efm_str == "" then
			return
		end

		if res == 1 then -- Filetype
			local ft = util.UserInput("Filetype:", vim.bo.ft == "oz_make" and "" or vim.bo.ft)
			if ft and ft ~= "" then
				cache.set_data(ft, efm_str, "oz_make_efm_ft")
				util.Notify("Saved EFM for " .. ft, "info", "oz_make")
			end
		elseif res == 2 then -- Project
			local project_root = dir or util.GetProjectRoot()
			if project_root then
				cache.set_data(project_root, efm_str, "oz_make_efm_project")
				util.Notify("Saved EFM for project", "info", "oz_make")
			end
		end
	end, { buffer = buf_id, desc = "Add EFM", silent = true })
	vim.keymap.set("n", "<cr>", function()
		-- jump to file
		local ok = pcall(vim.cmd, "normal! gF")

		if ok then
			local entry_buf = vim.api.nvim_get_current_buf()
			local pos = vim.api.nvim_win_get_cursor(0)

			vim.api.nvim_set_current_buf(buf_id)
			if entry_buf == buf_id then
				return
			end
			vim.cmd.wincmd("t")
			vim.api.nvim_set_current_buf(entry_buf)

			pcall(vim.api.nvim_win_set_cursor, 0, pos)
		else
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<cr>", true, false, true), "n", false)
		end
	end, { buffer = buf_id, desc = "Open the entry.", silent = true })

	-- Help
	vim.keymap.set("n", "g?", function()
        util.show_maps({})
	end, { buffer = buf_id, desc = "Show all available keymaps", silent = true })
end

-- show err in a wind
function M.makeout_win(lines, cmd, dir)
	local existing_win = nil
	for _, win_id in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win_id)
		local ok, name = pcall(vim.api.nvim_buf_get_var, buf, "oz_win_name")
		if ok and name == "makeout_win" then
			existing_win = win_id
			break
		end
	end

	if existing_win then
		vim.api.nvim_win_close(existing_win, true)
		return
	end

	local win_id, _ = util.create_win("makeout_win", {
		content = lines,
		win_type = "bot 7",
		reuse = true,
		callback = function(buf_id)
			-- mark it
			vim.api.nvim_buf_set_var(buf_id, "oz_win_name", "makeout_win")
			-- opts
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.opt_local.fillchars:append({ eob = " " })
			vim.bo.ft = "terminfo"

			-- mappings
			vim.fn.timer_start(100, function()
				make_err_buf_mappings(buf_id, cmd, dir)
			end)
		end,
	})

	if win_id and vim.api.nvim_win_is_valid(win_id) then
		pcall(vim.api.nvim_win_set_cursor, win_id, { #lines, 0 })
	end
end

-- Refresh output only if open
function M.refresh_makeout_win(lines)
	for _, win_id in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win_id)
		local ok, name = pcall(vim.api.nvim_buf_get_var, buf, "oz_win_name")
		if ok and name == "makeout_win" then
			util.create_win("makeout_win", {
				content = lines,
				win_type = "bot 7",
				reuse = true,
			})
			pcall(vim.api.nvim_win_set_cursor, win_id, { #lines, 0 })
			return true
		end
	end
	return false
end

return M
