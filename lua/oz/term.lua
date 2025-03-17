local M = {}
local util = require("oz.util")
local mapping_util = require("oz.mappings.util")
local grep = require("oz.grep")
local qf = require("oz.qf")

M.cached_cmd = nil
M.term_cmd_ft = nil

local term_buf = nil
local term_win = nil
local term_job_id = nil

-- run in term
function M.run_in_term(cmd, dir)
	M.term_cmd_ft = vim.bo.ft

	if not cmd then
		return
	else
		if grep.cmd_contains_grep(cmd) then
			local ans = util.prompt("oz: add to quickfix?", "&quickfix\n&oz_term", 1, "Info")
			if ans == 1 then
				grep.grep_to_qf(cmd, dir)
				return
			elseif not ans then
				return
			end
		end
		M.cached_cmd = cmd
	end
	if term_buf == nil or not vim.api.nvim_buf_is_valid(term_buf) then
		vim.cmd("split | resize 10") -- Open a vertical split
		term_buf = vim.api.nvim_create_buf(false, true) -- Create a new buffer
		vim.api.nvim_set_current_buf(term_buf) -- Set it as current buffer
		if dir then
			vim.cmd("lcd " .. dir .. " | terminal")
		else
			vim.cmd("terminal")
		end
		vim.api.nvim_buf_set_name(term_buf, "**oz_term**") -- naming the terminal buffer
		term_win = vim.api.nvim_get_current_win() -- Store the window

		-- if got deleted
		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = term_buf,
			callback = function()
				term_buf = nil
				term_win = nil
				term_job_id = nil
			end,
		})

		vim.bo.ft = "oz_term"
	elseif term_win == nil or not vim.api.nvim_win_is_valid(term_win) then
		vim.cmd("split | resize 10") -- Open a vertical split
		vim.api.nvim_set_current_buf(term_buf) -- Reuse the existing terminal buffer
		term_win = vim.api.nvim_get_current_win() -- Update window reference
	else
		vim.api.nvim_set_current_win(term_win)
	end
	term_job_id = vim.b[term_buf].terminal_job_id

	vim.api.nvim_chan_send(term_job_id, cmd .. "\n")
end

-- close term
function M.close_term()
	if term_buf and term_win then
		local job_id = vim.b[term_buf].terminal_job_id
		-- close job
		if job_id then
			vim.fn.jobstop(job_id)
		end

		-- close win
		if vim.api.nvim_win_is_valid(term_win) then
			vim.api.nvim_win_close(term_win, true)
		end
		-- close buf
		if vim.api.nvim_buf_is_valid(term_buf) then
			vim.api.nvim_buf_delete(term_buf, { force = true })
		end
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

local function term_cmd_init()
	-- Term - usercmd
	vim.api.nvim_create_user_command("Term", function(args)
		-- bang
		if args.bang then
			-- More than one args
			if args.args and #args.args > 0 then
				M.cached_cmd = args.args
				M.run_in_termbang(M.cached_cmd)
			else
				-- Re-execution
				M.run_in_termbang(M.cached_cmd)
			end
		else
			-- not bang
			-- More than one args
			if args.args and #args.args >= 2 then
				M.cached_cmd = args.args

				if M.cached_cmd then
					M.run_in_term(M.cached_cmd)
					util.Notify("running '" .. M.cached_cmd .. "'", nil, "oz_term")
				end
			else
				-- re running
				if M.cached_cmd then
					M.close_term()
					M.run_in_term(M.cached_cmd)
					util.Notify("reruning '" .. M.cached_cmd .. "'", nil, "oz_term")
				else
					util.Notify("Give a initial cmd to start oz_term", "warn", "oz_term")
				end
			end
		end
	end, { nargs = "*", bang = true, desc = "oz_term" })

	-- TermToggle - usercmd
	vim.api.nvim_create_user_command("TermToggle", function()
		if not term_buf or not term_buf or not term_job_id then
			return
		end
		if term_buf and not vim.api.nvim_win_is_valid(term_win) then
			vim.cmd("split | resize 10")
			vim.api.nvim_set_current_buf(term_buf)
			term_win = vim.api.nvim_get_current_win()
		elseif vim.api.nvim_win_is_valid(term_win) then
			vim.api.nvim_set_current_win(term_win)
			vim.cmd("close")
		end
	end, { desc = "toggle oz_term" })

	-- TermClose - usercmd
	vim.api.nvim_create_user_command("TermClose", function()
		if not term_buf or not term_buf or not term_job_id then
			return
		end
		M.close_term()
	end, { desc = "toggle oz_term" })
end

-- mappings
local function term_buf_mappings(config)
	util.Map("n", config.mappings.quit, function()
		local ans = util.prompt("oz: quit oz_term?", "&quit\n&no", 2, "Error")
		if ans == 1 then
			M.close_term()
		end
	end, { desc = "close oz_term", buffer = 0, silent = true })

	util.Map("n", config.mappings.rerun, ":Term<cr>", { desc = "rerun previous cmd", buffer = 0, silent = true })

	util.Map("n", config.mappings.add_to_quickfix, function()
		if not vim.api.nvim_buf_is_valid(term_buf) then
			vim.notify("Invalid buffer number: " .. term_buf, vim.log.levels.ERROR)
			return
		end
		local lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)

		qf.capture_lines_to_qf(lines, M.term_cmd_ft)
		if #vim.fn.getqflist() ~= 0 then
			vim.cmd.wincmd("p")
			vim.cmd("cfirst")
		else
			print("Nothing to add")
		end
	end, { desc = "add any {err|warn|stacktrace} to quickfix(*)", buffer = 0, silent = true })

	util.Map("n", config.mappings.open_entry, function()
		-- if url
		if vim.api.nvim_get_current_line():match([[https?://[^\s]+]]) then
			local ok = pcall(vim.cmd, "normal gx")
			if ok then
				return
			end
		end
		-- jump to file
		local ok = pcall(vim.cmd, "normal! gF")

		if ok then
			local entry_buf = vim.api.nvim_get_current_buf()
			local pos = vim.api.nvim_win_get_cursor(0)

			vim.api.nvim_set_current_buf(term_buf)
			if entry_buf == term_buf then
				return
			end
			vim.cmd.wincmd("k")
			vim.api.nvim_set_current_buf(entry_buf)

			pcall(vim.api.nvim_win_set_cursor, 0, pos)
		else
			util.Notify("entry under cursor is out of scope.", "warn", "oz")
		end
	end, { desc = "open entry(file, dir) under cursor(*)", buffer = 0, silent = true })

	util.Map("n", config.mappings.show_keybinds, function()
		util.Show_buf_keymaps({
			subtext = { "(*): have limited usablity" },
		})
	end, { desc = "show keymaps", noremap = true, silent = true, buffer = 0 })

	util.Map("n", config.mappings.open_in_compile_mode, function()
		M.close_term()
		mapping_util.cmd_func("Compile")
	end, { buffer = 0, silent = true, desc = "open in compile_mode" })
end

-- Term init
function M.Term_init(config)
	-- :Term init
	term_cmd_init()

	-- oz_term only autocmd
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "oz_term" },
		callback = function()
			-- options
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap winfixheight nomodifiable]])

			-- mappings
			vim.schedule(function()
				term_buf_mappings(config)
			end)
		end,
	})
end

return M
