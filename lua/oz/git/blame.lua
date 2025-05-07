local M = {}
local shell = require("oz.util.shell")
local win = require("oz.util.win")
local util = require("oz.util")

local source_buf_autocmd_id, target_buf_autocmd_id, blame_buf

---update cursor between two buffer
---@param buf1 integer
---@param buf2 integer
function M.update_cursor(buf1, buf2)
	local win1 = vim.fn.bufwinid(buf1)
	local win2 = vim.fn.bufwinid(buf2)
	if win1 ~= -1 and win2 ~= -1 then
		local cursor1 = vim.api.nvim_win_get_cursor(win1)
		local cursor2 = vim.api.nvim_win_get_cursor(win2)
		if cursor1[1] ~= cursor2[1] or cursor1[2] ~= cursor2[2] then
			if vim.api.nvim_get_current_win() == win1 then
				vim.api.nvim_win_call(win2, function()
					vim.api.nvim_win_set_cursor(win2, { cursor1[1], cursor1[2] })
				end)
			else
				vim.api.nvim_win_call(win1, function()
					vim.api.nvim_win_set_cursor(win1, { cursor2[1], cursor2[2] })
				end)
			end
		end
	end
end

---Cursor sync
---@param source_buf integer
---@param target_buf integer
local function sync_cursor(source_buf, target_buf)
	source_buf_autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = source_buf,
		callback = function()
			if vim.api.nvim_buf_is_valid(source_buf) then
				M.update_cursor(source_buf, target_buf)
			else
				vim.api.nvim_del_autocmd(source_buf_autocmd_id)
				vim.api.nvim_del_autocmd(target_buf_autocmd_id)
			end
		end,
	})

	target_buf_autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = target_buf,
		callback = function()
			if vim.api.nvim_buf_is_valid(target_buf) then
				M.update_cursor(source_buf, target_buf)
			else
				vim.api.nvim_del_autocmd(source_buf_autocmd_id)
				vim.api.nvim_del_autocmd(target_buf_autocmd_id)
			end
		end,
	})
end

-- balme buffer hl
local function blame_buf_hl()
	vim.cmd("syntax clear")

	vim.cmd([[
        syntax match @attribute /[0-9a-f]\{7,40\}/
        syntax match NonText /^[0]\{7,40\}.*$/
        syntax match @string /\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}:\d\{2} [+-]\d\{4}/
    ]])
end

-- blame buf mappings
local function blame_buf_maps(buf)
	local map = util.Map
	map("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close blame buffer." })

	map("n", "<cr>", function()
		local line = vim.api.nvim_get_current_line()
		local hash = line:match("^([^ ]+)")
		vim.cmd("Git show " .. hash)
	end, { buffer = buf, desc = "Show commit for current line." })
end

local function autocmd_func(buf)
	-- if blame buf removed
	vim.api.nvim_create_autocmd({ "BufHidden", "BufDelete" }, {
		buffer = buf,
		callback = function()
			vim.api.nvim_del_autocmd(source_buf_autocmd_id)
			vim.api.nvim_del_autocmd(target_buf_autocmd_id)

			blame_buf = nil
		end,
	})
end

---Format blame lines
---@param lines table
---@return table
local function format_blame_lines(lines)
	local formated = {}
	for _, line in ipairs(lines) do
		local pos = line:find(")")
		table.insert(formated, line:sub(1, pos))
	end
	return formated
end

---init
---@param file string|nil
function M.git_blame_init(file)
	-- if blame buffer open then close
	if blame_buf then
		vim.api.nvim_buf_delete(blame_buf, { force = true })
		blame_buf = nil
		return
	end

	local cur_file = file or vim.fn.expand("%")
	local file_buf = vim.fn.bufnr(cur_file)
	-- local file_win = vim.fn.bufwinid(file_buf)
	local file_cursor_pos = vim.api.nvim_win_get_cursor(0)

	local ok, output = shell.run_command({ "git", "blame", cur_file })
	if ok and #output > 0 then
		output = format_blame_lines(output)

		-- open blame win
		local win_type = string.format("vert %s", #output[#output])
		win.open_win("git_blame", {
			lines = output,
			win_type = win_type,
			callback = function(buf_id, win_id)
				blame_buf = buf_id
				vim.cmd(
					[[setlocal cursorline ft=oz_git signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]]
				)
				pcall(vim.api.nvim_win_set_cursor, win_id, file_cursor_pos) -- set cursor pos

				-- highlight
				blame_buf_hl()

				-- mappings
				blame_buf_maps(buf_id)

				-- go back to the main buffer
				vim.cmd.wincmd("p")
			end,
		})

		-- start cursor syncing
		if blame_buf then
			sync_cursor(file_buf, blame_buf)
		end

		autocmd_func(blame_buf)
	end
end

return M
