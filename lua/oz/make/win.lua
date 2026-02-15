local M = {}
local util = require("oz.util")
local win = require("oz.util.win")

-- make err win buffer mappings
local function make_err_buf_mappings(buf_id, cmd, dir)
	util.Map("n", "q", "<cmd>close<cr>", { buffer = buf_id, desc = "Close" })
	util.Map("n", "t", function()
		require("oz.term").run_in_term(cmd, dir)
	end, { buffer = buf_id, desc = "Run in term" })
	util.Map("n", "<cr>", function()
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
	end, { buffer = buf_id, desc = "Open the entry." })

	-- Help
	vim.keymap.set("n", "g?", function()
		require("oz.util.help_keymaps").show_maps({})
	end, { buffer = buf_id, desc = "Show all available keymaps" })
end

-- show err in a wind
function M.make_err_win(lines, cmd, dir)
	local win_id, buf_id = win.create_win("make_err", {
		content = lines,
		win_type = "bot 7",
		reuse = true,
		callback = function(buf_id)
			-- opts
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.opt_local.fillchars:append({ eob = " " })
			local shell_name = vim.fn.fnamemodify(vim.fn.environ()["SHELL"] or vim.fn.environ()["COMSPEC"], ":t:r")
			if shell_name == "bash" or shell_name == "zsh" then
				vim.bo.ft = "sh"
			elseif shell_name == "powershell" then
				vim.bo.ft = "ps1"
			else
				vim.bo.ft = shell_name
			end

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

return M
