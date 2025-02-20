local M = {}
local util = require("oz.util")

local cachedCmd = nil
local cwd = nil

local term_buf = nil
local term_win = nil
function M.run_in_term(cmd, dir)
	if term_buf == nil or not vim.api.nvim_buf_is_valid(term_buf) then
		vim.cmd("split") -- Open a vertical split
		term_buf = vim.api.nvim_create_buf(false, true) -- Create a new buffer
		vim.api.nvim_set_current_buf(term_buf) -- Set it as current buffer
		if dir then
			vim.cmd("lcd " .. dir .. " | terminal")
		elseif cmd:match("@") then
			cmd = cmd:gsub("@", "")
			local wd = util.GetProjectRoot() or vim.fn.getcwd()
			vim.cmd("lcd " .. wd .. " | terminal")
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

	vim.api.nvim_chan_send(vim.b.terminal_job_id, cmd .. "\n")
end

function M.close_term()
	local job_id = vim.b[term_buf].terminal_job_id
	if job_id then
		vim.fn.jobstop(job_id)
	end
	if vim.api.nvim_win_is_valid(term_win) then
		vim.api.nvim_win_close(term_win, true)
	end
	if vim.api.nvim_buf_is_valid(term_buf) then
		vim.api.nvim_buf_delete(term_buf, { force = true })
	end
end

function M.Term(a)
	vim.api.nvim_create_user_command("Term", function(args)
		local function run_extern(cmd)
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
				run_extern(cachedCmd)
			else
				run_extern(cachedCmd)
			end
		else
			if args.args and #args.args >= 2 then
				cachedCmd = args.args
			end
			if cachedCmd then
				vim.notify("Executing '" .. cachedCmd .. "' ..")
				if term_buf and term_win then
					M.close_term()
				end
				M.run_in_term(cachedCmd)
			end
		end
	end, { nargs = "*", bang = true })

	-- oz_term only autocmd
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "oz_term" },
		callback = function(event)
			-- options
			vim.cmd([[resize 10]])
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap winfixheight nomodifiable]])
			cwd = vim.fn.getcwd()

			-- mappings
			util.Map("n", a.keys.quit, function()
				M.close_term()
			end, { desc = "close oz_term", buffer = event.buf, silent = true })

			util.Map("n", a.keys.rerun, ":Term<cr>", { desc = "rerun previous cmd", buffer = event.buf, silent = true })

            util.Map("n", a.keys.add_to_quickfix, function()
				vim.cmd(
					[[cgetexpr filter(getline(1, '$'), 'v:val =~? "\\v(error|warn|warning|err|issue|stacktrace)"')]]
				)
				if #vim.fn.getqflist() ~= 0 then
					vim.cmd.wincmd("p")
					vim.cmd("cfirst")
				else
					print("Nothing to add")
				end
			end, { desc = "add any {err|warn|stacktrace} to quickfix(*)", buffer = event.buf, silent = true })

			util.Map("n", a.keys.open_entry, function()
				local cfile = vim.fn.expand("<cfile>")
				local full_path = vim.fn.resolve(cwd .. "/" .. cfile)

				if vim.fn.filereadable(full_path) == 1 then
					vim.schedule(function()
						vim.cmd.wincmd("k")
						vim.cmd("e " .. full_path)
					end)
				elseif vim.fn.isdirectory(full_path) == 1 then
					vim.schedule(function()
						vim.cmd.wincmd("k")
						vim.cmd("e " .. full_path .. "/")
					end)
				else
					util.Notify("out of scope", "warn", "oz_term")
				end
			end, { desc = "open entry(file, dir) under cursor(*)", buffer = event.buf, silent = true })

            util.Map("n", a.keys.show_keybinds, function()
				util.Show_buf_keymaps({
					subtext = { "(*): have limited usablity" },
				})
			end, { desc = "show keymaps", noremap = true, silent = true, buffer = event.buf })
		end,
	})
end

return M
