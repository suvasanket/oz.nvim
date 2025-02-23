local M = {}
local util = require("oz.util")
local mapping_util = require("oz.mappings.util")
local grep = require("oz.grep")

M.cached_cmd = nil

local term_buf = nil
local term_win = nil

-- run in term
function M.run_in_term(cmd, dir)
	if not cmd then
		return
	else
		if grep.cmd_contains_grep(cmd) then
			local ans = util.prompt("oz: add to quickfix?", "&quickfix\n&oz_term", 1, "Info")
			if ans == 1 then
				grep.run_vim_grep(cmd, dir)
				return
			elseif not ans then
				return
			end
		end
		M.cached_cmd = cmd
	end
	if term_buf == nil or not vim.api.nvim_buf_is_valid(term_buf) then
		vim.cmd("split") -- Open a vertical split
		term_buf = vim.api.nvim_create_buf(false, true) -- Create a new buffer
		vim.api.nvim_set_current_buf(term_buf) -- Set it as current buffer
		if dir then
			vim.cmd("lcd " .. dir .. " | terminal")
		else
			vim.cmd("terminal")
		end
		vim.api.nvim_buf_set_name(term_buf, "oz_term:'" .. cmd .. "'") -- naming the terminal buffer
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

-- close term
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

-- run in term!
function M.run_in_termbang(cmd, dir)
	local inside_tmux = os.getenv("TMUX") ~= nil

	if inside_tmux then
		local tmux_cmd = [[tmux neww -c {path} -n 'Term!' -d '{cmd}']]
		dir = dir or "."
		tmux_cmd = tmux_cmd:gsub("{cmd}", cmd):gsub("{path}", dir)
		vim.fn.system(tmux_cmd)
	else
		vim.cmd("tab term " .. "cd " .. dir .. " && " .. cmd)
	end
	vim.notify("Executing '" .. cmd .. "' ..")
end

-- Term init
function M.Term(config)
	vim.api.nvim_create_user_command("Term", function(args)
		if args.bang then
			if args.args and #args.args > 0 then
				M.cached_cmd = args.args
				M.run_in_termbang(M.cached_cmd)
			else
				M.run_in_termbang(M.cached_cmd)
			end
		else
			if args.args and #args.args >= 2 then
				M.cached_cmd = args.args
			end
			if M.cached_cmd then
				vim.notify("Executing '" .. M.cached_cmd .. "' ..")
				if term_buf and term_win then
					M.close_term()
				end
				M.run_in_term(M.cached_cmd)
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

			-- mappings
			util.Map("n", config.mappings.quit, function()
				local ans = util.prompt("oz: quit oz_term?", "&quit\n&no", 2, "Error")
				if ans == 1 then
					M.close_term()
				end
			end, { desc = "close oz_term", buffer = event.buf, silent = true })

			util.Map(
				"n",
				config.mappings.rerun,
				":Term<cr>",
				{ desc = "rerun previous cmd", buffer = event.buf, silent = true }
			)

			util.Map("n", config.mappings.add_to_quickfix, function()
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

			util.Map("n", config.mappings.open_entry, function()
				if vim.api.nvim_get_current_line():match([[https?://[^\s]+]]) then
					local ok = pcall(vim.cmd, "normal gx")
					if ok then
						return
					end
				end
				local ok = pcall(vim.cmd, "normal! gF")

				if ok then
					local entry_buf = vim.api.nvim_get_current_buf()
					vim.api.nvim_set_current_buf(term_buf)
					if entry_buf == term_buf then
						return
					end
					vim.cmd.wincmd("k")
					vim.api.nvim_set_current_buf(entry_buf)
				else
					util.Notify("can't open the current entry", "error", "oz")
				end
			end, { desc = "open entry(file, dir) under cursor(*)", buffer = event.buf, silent = true })

			util.Map("n", config.mappings.show_keybinds, function()
				util.Show_buf_keymaps({
					subtext = { "(*): have limited usablity" },
				})
			end, { desc = "show keymaps", noremap = true, silent = true, buffer = event.buf })

			util.Map("n", config.mappings.open_in_compile_mode, function()
				M.close_term()
				mapping_util.cmd_func("Compile")
			end, { buffer = event.buf, silent = true, desc = "open in compile_mode" })
		end,
	})
end

return M
