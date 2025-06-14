local M = {}
local util = require("oz.util")
local shell = require("oz.util.shell")
local state = require("oz.git.status").state
-- local status = require("oz.git.status")

--
M.headings_table = {}
M.diff_lines = {}
M.toggled_headings = {}

local run_cmd = shell.run_command
-- local shellout_str = shell.shellout_str

function M.get_heading_tbl(lines)
	if #lines <= 0 then
		return
	end
	M.headings_table = {}
	local current_heading = nil
	local _, branch_line = run_cmd({ "git", "branch", "-vv" }, state.cwd)
	local branch_heading = "On branch " .. state.current_branch

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

function M.toggle_section(arg_heading)
	local buf = require("oz.git.status").status_buf
	local current_line = arg_heading or vim.api.nvim_get_current_line()
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

		if not arg_heading then -- adding toggled lines to the M.toggeled_headings
			local toggled_lines = current_line:match("^(%w+%s+%w+)") -- split out the first two words
			if vim.list_contains(M.toggled_headings, toggled_lines) then
				util.remove_from_tbl(M.toggled_headings, toggled_lines)
			else
				util.tbl_insert(M.toggled_headings, toggled_lines)
			end
		end

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

---get the file/dir under cursor
---@param fmt_origin boolean|nil
---@return table
function M.get_file_under_cursor(fmt_origin)
	local entries = {}
	local lines = {}
	-- local cwd = require("oz.git.status").state.cwd or vim.fn.getcwd()
	local root = require("oz.git").state.root or util.GetProjectRoot()

	if vim.api.nvim_get_mode().mode == "n" then
		local line = vim.fn.getline(".")
		table.insert(lines, line)
	else
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
		-- vim.api.nvim_input("<Esc>")
	end

	for _, line in ipairs(lines) do
		local file = line:match("%S+$")
		local dir = line:match("(%S+/)")

		local tbl = { "deleted:", "renamed:", "copied:" }
		local absolute_dir_path, absolute_file_path
		if file then
			absolute_file_path = root .. "/" .. file
		elseif dir then
			absolute_dir_path = root .. "/" .. dir
		end

		if vim.fn.filereadable(absolute_file_path) == 1 then -- file
			if fmt_origin then
				table.insert(entries, file)
			else
				table.insert(entries, absolute_file_path)
			end
		elseif vim.fn.isdirectory(absolute_dir_path) == 1 then -- dir
			if fmt_origin then
				table.insert(entries, dir)
			else
				table.insert(entries, absolute_dir_path)
			end
		else
			for _, string in pairs(tbl) do
				if line:find(string) then
					table.insert(entries, file)
				end
			end
		end
	end

	return entries
end

function M.get_branch_under_cursor()
	local branch_heading = "On branch " .. require("oz.git.status").state.current_branch
	local tbl = M.headings_table[branch_heading]
	local current_line = vim.api.nvim_get_current_line()

	if vim.tbl_contains(tbl, current_line) then
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

	local _, diff = run_cmd({ "git", "diff", file }, state.cwd)
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

--- get stash under cursor
---@return {index: integer, branch: string, name: string}
function M.get_stash_under_cursor()
	local line_content = vim.api.nvim_get_current_line()
	local pattern = "^%s*stash@{(%d+)}:%s*On%s+(.-):%s*(.+)$"

	local index_str, branch_name, stash_name = line_content:match(pattern)

	if index_str and branch_name and stash_name then
		local index_num = tonumber(index_str)

		branch_name = branch_name:match("^%s*(.-)%s*$") or branch_name
		stash_name = stash_name:match("^%s*(.-)%s*$") or stash_name

		return {
			index = index_num,
			branch = branch_name,
			name = stash_name,
		}
	else
		return {}
	end
end

return M
