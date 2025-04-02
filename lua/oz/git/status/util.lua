local M = {}
local util = require("oz.util")
local status = require("oz.git.status")

--
M.headings_table = {}
M.diff_lines = {}
M.opened_headings = {}

function M.get_heading_tbl(lines)
	if #lines <= 0 then
		return
	end
	M.headings_table = {}
	local current_heading = nil
	local branch_line = util.ShellOutputList("git branch -v")
	local branch_heading = "On branch " .. status.current_branch

	M.headings_table[branch_heading] = {}
	for _, line in ipairs(branch_line) do
		if line ~= "" then
			line = "  " .. line
			table.insert(M.headings_table[branch_heading], line)
		end
	end

	for _, line in ipairs(lines) do
		if
			line:match("^Changes not staged for commit:")
			or line:match("^Untracked files:")
			or line:match("^Changes to be committed:")
			or line:match("Stash list:")
		then
			current_heading = line
			M.headings_table[current_heading] = {}
		elseif current_heading and line ~= "" then
			table.insert(M.headings_table[current_heading], line)
		elseif line == "" then
			current_heading = nil
		end
	end

	return M.headings_table
end

local function find_line_number(line_content)
	local buf = require("oz.git.status").status_buf
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	for i, line in ipairs(lines) do
		if line == line_content then
			return i
		end
	end
	return nil
end

function M.toggle_section(user_head)
	local buf = require("oz.git.status").status_buf
	local current_line = user_head or vim.api.nvim_get_current_line()
	local line_num = find_line_number(current_line)
    if not line_num then
        return nil
    end

	-- Check if the current line is a heading
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	if M.headings_table[current_line] then
		local next_line = line_num + 1
		local next_lines = vim.api.nvim_buf_get_lines(buf, next_line - 1, next_line, false)
		local next_line_content = next_lines[1]

		util.tbl_insert(M.opened_headings, current_line)

		if next_line_content and next_line_content:match("^%s") then
			-- If the next line is indented, collapse the content
			while next_line_content and next_line_content:match("^%s") do
				vim.api.nvim_buf_set_lines(buf, next_line - 1, next_line, false, {})
				next_lines = vim.api.nvim_buf_get_lines(buf, next_line - 1, next_line, false)
				next_line_content = next_lines[1]
			end
		else
			-- If the next line is not indented, expand the content
			local content = M.headings_table[current_line]
			vim.api.nvim_buf_set_lines(buf, line_num, line_num, false, content)
		end
	end
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

function M.get_file_under_cursor(original)
	local entries = {}
	local lines = {}
	local cwd = CWD or vim.fn.getcwd()
	if vim.api.nvim_get_mode().mode == "n" then
		local line = vim.fn.getline(".")
		table.insert(lines, line)
	else
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
		vim.api.nvim_input("<Esc>")
	end

	for _, line in ipairs(lines) do
		local file = line:match("%S+$")
		local dir = line:match("(%S+/)")

		local absolute_file_path = vim.fs.normalize(cwd .. "/" .. file)
		local absolute_dir_path
		if dir then
			absolute_dir_path = vim.fs.normalize(cwd .. "/" .. dir)
		end
		local tbl = { "deleted:", "renamed:", "copied:" }

		if vim.fn.filereadable(absolute_file_path) == 1 then
			if original then
				table.insert(entries, file)
			else
				table.insert(entries, absolute_file_path)
			end
		elseif vim.fn.isdirectory(absolute_dir_path) == 1 then
			if original then
				table.insert(entries, dir)
			else
				table.insert(entries, absolute_dir_path)
			end
		elseif util.str_in_tbl(line, tbl) then
			if original then
				table.insert(entries, file)
			else
				table.insert(entries, absolute_file_path)
			end
		end
	end

	return entries
end

function M.get_branch_under_cursor()
	local branch_heading = "On branch " .. status.current_branch
	local tbl = M.headings_table[branch_heading]
	local current_line = vim.api.nvim_get_current_line()

	if util.str_in_tbl(current_line, tbl) then
		current_line = vim.trim(current_line:gsub("%*", ""))
		return vim.trim(current_line:match("^%s*(%S+)"))
	else
		return nil
	end
end

function M.generate_diff(file)
	if not file then
		return nil
	end

	local diff = util.ShellOutputList("git diff " .. file)
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

function M.toggle_diff()
	local file = M.get_file_under_cursor() -- Get the file under the cursor
	if #file > 0 then
		file = file[1]
	else
		return
	end

	local line_num = vim.fn.line(".") -- Get the current line number

	-- Check if the diff is already shown
	if M.diff_lines[file] then
		vim.bo.modifiable = true
		vim.api.nvim_buf_set_lines(0, line_num, line_num + #M.diff_lines[file], false, {})
		vim.bo.modifiable = false
		M.diff_lines[file] = nil -- Clear the stored diff lines
	else
		-- If diff is not shown, generate and insert it
		local diff = M.generate_diff(file)
		if not diff or #diff == 0 then
			return
		end
		vim.bo.modifiable = true
		vim.api.nvim_buf_set_lines(0, line_num, line_num, false, diff) -- Insert diff lines
		vim.bo.modifiable = false
		M.diff_lines[file] = diff
	end
end

return M
