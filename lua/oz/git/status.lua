local M = {}
local util = require("oz.util")

local status_win = nil
local status_buf = nil
local status_win_height = 14
local cwd = nil

local headings_table = {}
local diff_lines = {}

-- helper: heading tbl.
local function get_heading_tbl(lines)
	local current_heading = nil
	local branch_line = vim.fn.systemlist("git branch")
	local branch_heading = "On branch " .. vim.trim(util.ShellOutput("git branch --show-current"))

	headings_table[branch_heading] = {}
	for _, line in ipairs(branch_line) do
		if line ~= "" then
			line = "\t" .. line
			table.insert(headings_table[branch_heading], line)
		end
	end

	for _, line in ipairs(lines) do
		if
			line:match("^Changes not staged for commit:")
			or line:match("^Untracked files:")
			or line:match("^Changes to be committed:")
		then
			current_heading = line
			headings_table[current_heading] = {}
		elseif current_heading and line ~= "" then
			table.insert(headings_table[current_heading], line)
		elseif line == "" then
			current_heading = nil
		end
	end
end

-- Function to toggle the visibility of a heading's content
local function toggle_section()
	local line_num = vim.fn.line(".") -- Get the current line number
	local current_line = vim.api.nvim_get_current_line()

	-- Check if the current line is a heading
	vim.bo.modifiable = true
	if headings_table[current_line] then
		local next_line = line_num + 1
		local next_lines = vim.api.nvim_buf_get_lines(0, next_line - 1, next_line, false)
		local next_line_content = next_lines[1]

		if next_line_content and next_line_content:match("^%s") then
			-- If the next line is indented, collapse the content
			while next_line_content and next_line_content:match("^%s") do
				vim.api.nvim_buf_set_lines(0, next_line - 1, next_line, false, {})
				next_lines = vim.api.nvim_buf_get_lines(0, next_line - 1, next_line, false)
				next_line_content = next_lines[1]
			end
		else
			-- If the next line is not indented, expand the content
			local content = headings_table[current_line]
			vim.api.nvim_buf_set_lines(0, line_num, line_num, false, content)
		end
	end
	vim.bo.modifiable = false
end

-- Function to get the file path under the cursor
local function get_file_under_cursor()
	local entries = {}
	local lines = {}
	if vim.api.nvim_get_mode().mode == "n" then
		local line = vim.fn.getline(".")
		table.insert(lines, line)
	else
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	end

	for _, line in ipairs(lines) do
		local file = line:match("%S+$")
		cwd = cwd or vim.fn.getcwd()
		local absolute_path = vim.fs.normalize(cwd .. "/" .. file)
		local tbl = { "deleted:", "renamed:", "copied:" }
		if vim.fn.filereadable(absolute_path) == 1 or vim.fn.isdirectory(absolute_path) == 1 then
			table.insert(entries, absolute_path)
		elseif util.str_in_tbl(line, tbl) then
			table.insert(entries, absolute_path)
		end
	end

	return entries
end

-- Function to generate diff for a file
local function generate_diff(file)
	if not file then
		return nil
	end

	local diff = vim.fn.systemlist("git diff " .. file)
	local new_diff = {}
	local grab = false

	for _, line in ipairs(diff) do
		if line:match("^@") then
			grab = true
		end
		if grab then
			table.insert(new_diff, "    " .. line)
		end
	end

	return new_diff
end

local function toggle_diff()
	local file = get_file_under_cursor() -- Get the file under the cursor
	if #file > 0 then
		file = file[1]
	else
		return
	end

	local line_num = vim.fn.line(".") -- Get the current line number

	-- Check if the diff is already shown
	if diff_lines[file] then
		vim.bo.modifiable = true
		vim.api.nvim_buf_set_lines(0, line_num, line_num + #diff_lines[file], false, {})
		vim.bo.modifiable = false
		diff_lines[file] = nil -- Clear the stored diff lines
	else
		-- If diff is not shown, generate and insert it
		local diff = generate_diff(file)
		if not diff or #diff == 0 then
			return
		end
		vim.bo.modifiable = true
		vim.api.nvim_buf_set_lines(0, line_num, line_num, false, diff) -- Insert diff lines
		vim.bo.modifiable = false
		diff_lines[file] = diff -- Store the diff lines for toggling
	end
end

-- status buffer keymaps
local function status_buf_keymaps(buf)
	-- quit
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "close git status buffer." })

	-- tab
	vim.keymap.set("n", "<tab>", function()
		if not toggle_diff() then
			toggle_section()
		end
	end, { buffer = buf, silent = true, desc = "Toggle headings/file-diff." })

	vim.keymap.set("n", "<C-r>", function()
		M.refresh_status_buf()
	end, { buffer = buf, silent = true, desc = "Refresh status buffer." })

	-- stage
	vim.keymap.set({ "n", "x" }, "s", function()
		local entries = get_file_under_cursor()
		local current_line = vim.api.nvim_get_current_line()

		if #entries > 0 then
			util.ShellCmd({ "git", "add", unpack(entries) }, function()
				M.refresh_status_buf()
			end, function()
				util.Notify("cannot stage selected.", "error", "oz_git")
			end)
		elseif current_line:find("Changes not staged for commit:") then
			util.ShellCmd({ "git", "add", "-u" }, function()
				M.refresh_status_buf()
			end, function()
				util.Notify("cannot stage selected.", "error", "oz_git")
			end)
		elseif current_line:find("Untracked files:") then
			vim.api.nvim_feedkeys(":Git add .", "n", false)
		end
	end, { remap = false, buffer = buf, silent = true, desc = "stage entry under cursor or selected entries." })

	-- unstage
	vim.keymap.set({ "n", "x" }, "u", function()
		local entries = get_file_under_cursor()
		local current_line = vim.api.nvim_get_current_line()

		if #entries > 0 then
			util.ShellCmd({ "git", "restore", "--staged", unpack(entries) }, function()
				M.refresh_status_buf()
			end, function()
				util.Notify("cannot unstage currently selected.", "error", "oz_git")
			end)
		elseif current_line:find("Changes to be committed:") then
			util.ShellCmd({ "git", "reset" }, function()
				M.refresh_status_buf()
			end, function()
				util.Notify("cannot unstage currently selected.", "error", "oz_git")
			end)
		end
	end, { remap = false, buffer = buf, silent = true, desc = "unstage entry under cursor or selected entries." })

	-- discard
	vim.keymap.set({ "n", "x" }, "X", function()
		local entries = get_file_under_cursor()
		if #entries > 0 then
			util.ShellCmd({ "git", "restore", unpack(entries) }, function()
				M.refresh_status_buf()
			end, function()
				util.Notify("cannot discard currently selected.", "error", "oz_git")
			end)
		end
	end, { remap = false, buffer = buf, silent = true, desc = "discard entry under cursor or selected entries." })

	-- untrack
	vim.keymap.set({ "n", "x" }, "K", function()
		local entries = get_file_under_cursor()
		if #entries > 0 then
			util.ShellCmd({ "git", "rm", "--cached", unpack(entries) }, function()
				M.refresh_status_buf()
			end, function()
				util.Notify("cannot remove from tracking currently selected.", "error", "oz_git")
			end)
		end
	end, { remap = false, buffer = buf, silent = true, desc = "untrack entry under cursor or selected entries." })

	-- commit
	vim.keymap.set("n", "cc", function()
		vim.cmd("Git commit")
	end, { remap = false, buffer = buf, silent = true, desc = "open commit buffer." })

	-- open current entry
	vim.keymap.set("n", "<cr>", function()
		local entry = get_file_under_cursor()
		if #entry > 0 then
			if vim.fn.filereadable(entry[1]) == 1 or vim.fn.isdirectory(entry[1]) == 1 then
				vim.cmd.wincmd("p")
				vim.cmd("edit " .. entry[1])
			end
		else
			-- change branch
			local current_line = vim.trim(vim.api.nvim_get_current_line())
			local branch_heading = "On branch " .. vim.trim(util.ShellOutput("git branch --show-current"))
			for _, str in pairs(headings_table[branch_heading]) do
				local line = str:gsub("^[^w%s]+", ""):gsub("^%s+", "")
				if line == current_line then
					require("oz.git").after_exec_complete(function()
						M.refresh_status_buf()
					end)
					line = vim.trim(line:gsub("%*", ""))
					vim.cmd("Git checkout " .. line)
				end
			end
		end
	end, { remap = false, buffer = buf, silent = true, desc = "open entry under cursor." })

	-- commit log
	vim.keymap.set("n", "gl", function()
		vim.cmd("close")
		require("oz.git.git_log").commit_log({ level = 1, from = "Git" })
	end, { remap = false, buffer = buf, silent = true, desc = "goto commit logs." })

	-- help
	vim.keymap.set("n", "g?", function()
		util.Show_buf_keymaps()
	end, { remap = false, buffer = buf, silent = true, desc = "show all availble keymaps." })
end

-- hl
local function status_buf_hl()
	vim.cmd("syntax clear")

	vim.cmd([[syntax match ozgitstatusDeleted /^\s\+deleted:\s\+.*$/]])
	vim.cmd([[syntax match ozgitstatusModified /^\s\+modified:\s\+.*$/]])
	vim.api.nvim_set_hl(0, "ozgitstatusDeleted", { fg = "#757575" })
	vim.cmd("highlight default link ozgitstatusModified MoreMsg")

	-- diff
	vim.cmd([[
    syntax match ozgitstatusDiffAdded /^    +.\+$/
    syntax match ozgitstatusDiffRemoved /^    -.\+$/
    highlight default link ozgitstatusDiffAdded @diff.plus
    highlight default link ozgitstatusDiffRemoved @diff.minus
    ]])

	-- headings
	vim.cmd([[
    syntax match NoIndentCapital /^[A-Z][^ \t].*/
    highlight link NoIndentCapital @function
    ]])

	-- branch
	vim.cmd([[
    syntax match ozGitStatusHeader "^On branch " nextgroup=ozGitStatusBranchName
    syntax match ozGitStatusBranchName "\S\+" contained

    highlight default link ozGitStatusBranchName Title
    highlight default link ozGitStatusHeader @function
    ]])

	-- remote branch
	vim.cmd([[
    highlight GitStatusLine guifg=#808080 ctermfg=244
    highlight GitStatusQuoted guifg=#99BC85 ctermfg=46 gui=italic
    highlight default link GitStatusNumber @warning

    syntax match GitStatusLine /^Your branch is ahead of '.*' by \d\+ commits\.$/
    syntax match GitStatusQuoted /'[^']*'/ contained containedin=GitStatusLine
    syntax match GitStatusNumber /\d\+/ contained containedin=GitStatusLine
    ]])
end

-- status buf FileType
local function status_buf_ft()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "GitStatus",
		once = true,
		callback = function(event)
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			status_buf_keymaps(event.buf)
			status_buf_hl()
		end,
	})
	return true
end

-- create and open the status
local function open_status_buf(lines)
	if status_buf == nil or not vim.api.nvim_win_is_valid(status_win) then
		status_buf = vim.api.nvim_create_buf(false, true)

		vim.cmd("botright " .. status_win_height .. " split")
		status_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(status_win, status_buf)

		vim.api.nvim_buf_set_lines(status_buf, 0, -1, false, lines)

		if status_buf_ft() then
			vim.api.nvim_buf_set_option(status_buf, "ft", "GitStatus")
		else
			vim.api.nvim_buf_set_option(status_buf, "ft", "oz_git")
		end

		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = status_buf,
			callback = function()
				status_buf = nil
				status_win = nil
				cwd = nil
			end,
		})
	else
		vim.api.nvim_set_current_win(status_win)
		vim.cmd("resize " .. status_win_height)
		vim.api.nvim_buf_set_option(status_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(status_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(status_buf, "modifiable", false)
	end
end

-- get neccessry lines for status buffer
local function get_status_lines()
	local status_tbl = {}
	local status_str = util.ShellOutput("git status")

	for substr in status_str:gmatch("([^\n]*)\n?") do
		if substr ~= "" and not substr:match('%(use "git .-.%)') then
			table.insert(status_tbl, substr)
		end
	end
	return status_tbl
end

function M.refresh_status_buf()
	local pos = vim.api.nvim_win_get_cursor(0)
	vim.cmd("close")
	M.GitStatus()
	pcall(vim.api.nvim_win_set_cursor, 0, pos)
end

-- Initialize status
function M.GitStatus()
	cwd = nil
	local status_lines = get_status_lines()
	get_heading_tbl(status_lines)

	open_status_buf(status_lines)
end

return M
