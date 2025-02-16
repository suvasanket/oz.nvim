local M = {}
local util = require("oz.util")

local cachedCmd = nil

local term_buf = nil
local term_win = nil
function M.run_in_term(cmd, dir)
	if term_buf == nil or not vim.api.nvim_buf_is_valid(term_buf) then
		vim.cmd("split | resize 10") -- Open a vertical split
		term_buf = vim.api.nvim_create_buf(false, true) -- Create a new buffer
		vim.api.nvim_set_current_buf(term_buf) -- Set it as current buffer
		if dir then
			print(dir)
			vim.cmd("lcd " .. dir .. " | terminal")
		elseif cmd:match("@") then
			cmd = cmd:gsub("@", "")
			vim.cmd("lcd " .. util.GetProjectRoot() .. " | terminal")
		else
			vim.cmd("terminal")
		end
		term_win = vim.api.nvim_get_current_win() -- Store the window
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = term_buf,
			callback = function()
				term_buf = nil
				term_win = nil
			end,
		})
		vim.bo.ft = "oz_term"
	elseif term_win == nil or not vim.api.nvim_win_is_valid(term_win) then
		vim.cmd("split") -- Open a vertical split again
		vim.api.nvim_set_current_buf(term_buf) -- Reuse the existing terminal buffer
		term_win = vim.api.nvim_get_current_win() -- Update window reference
	else
		vim.api.nvim_set_current_win(term_win)
	end

	vim.api.nvim_chan_send(vim.b.terminal_job_id, "clear\n" .. cmd .. "\n")
end

function M.Term()
	vim.api.nvim_create_user_command("Term", function(args)
		local function run_cached_or_new_term(cmd)
			if cmd then
				local inside_tmux = os.getenv("TMUX") ~= nil
				if inside_tmux then
					vim.fn.system("tmux neww -n 'Term!' -d " .. "'" .. cmd .. "'")
				else
					vim.cmd("tab term " .. cmd)
				end
				vim.notify("Executing '" .. cmd .. "' ..")
			end
		end

		if args.bang then
			if args.args and #args.args > 0 then
				cachedCmd = args.args
				run_cached_or_new_term(cachedCmd)
			else
				run_cached_or_new_term(cachedCmd)
			end
		else
			if args.args and #args.args >= 2 then
				cachedCmd = args.args
			end
			if cachedCmd then
				vim.notify("Executing '" .. cachedCmd .. "' ..")
				M.run_in_term(cachedCmd)
			end
		end
	end, { nargs = "*", bang = true })

	-- oz_term only autocmd
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "oz_term" },
		callback = function(event)
			vim.cmd("setlocal listchars= nonumber norelativenumber")
			vim.opt_local.wrap = false
			vim.keymap.set("n", "q", "i<C-d>", { desc = "close oz_term", buffer = event.buf, silent = true })
			vim.keymap.set("n", "r", ":Term<cr>", { desc = "rerun", buffer = event.buf, silent = true })

            vim.keymap.set("n", "cc", "iclear\n<C-\\><C-n>",  { desc = "clear", buffer = event.buf, silent = true, noremap = true })
            vim.keymap.set("t", "<C-S-\\>", "clear\n",  { desc = "clear", buffer = event.buf, silent = true, noremap = true })

			vim.keymap.set("n", "<cr>", function()
				local cfile = vim.fn.expand("<cfile>")
				local cwd = vim.fn.getcwd()
				local full_path = vim.fn.resolve(cwd .. "/" .. cfile)

				if vim.fn.filereadable(full_path) == 1 then
					vim.schedule(function()
						vim.cmd.wincmd("w")
						vim.cmd("e " .. full_path)
					end)
				elseif vim.fn.isdirectory(full_path) == 1 then
					vim.schedule(function()
						vim.cmd.wincmd("w")
						vim.cmd("e " .. full_path .. "/")
					end)
				else
					util.Notify("out of scope", "warn", "oz_term")
				end
			end, { desc = "open file", buffer = event.buf, silent = true })
		end,
	})
end

return M
