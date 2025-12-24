local M = {}
local util = require("oz.util")
local git = require("oz.git")

-- Render the buffer based on M.state
function M.render(buf)
	local status = require("oz.git.status")
	local state = status.state
	local order = status.render_order
	local icons = status.icons
	local ns_id = vim.api.nvim_create_namespace("oz_git_status_icons")

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local lines = {}
	local header_meta = {}
	local info_lines = {}

	for _, section_id in ipairs(order) do
		local section = state.sections[section_id]

		if section and (#section.content > 0 or section_id == "branch") then
			-- 1. Header with Icon
			local icon = section.collapsed and icons.collapsed or icons.expanded
			local display_header = string.format("%s %s", icon, section.header)

			table.insert(lines, display_header)

			-- Store metadata for highlighting
			table.insert(header_meta, {
				line = #lines - 1,
				icon_len = #icon,
				id = section_id, -- Store ID to distinguish branch section
			})

			-- 2. Content
			if not section.collapsed then
				for _, line in ipairs(section.content) do
					table.insert(lines, line)
				end
			end

			-- 3. Info Line
			if section_id == "branch" and state.info_lines and #state.info_lines > 0 then
				for _, info in ipairs(state.info_lines) do
					table.insert(lines, "  " .. info)
					table.insert(info_lines, #lines - 1)
				end
			end

			table.insert(lines, "")
		end
	end

	if lines[#lines] == "" then
		table.remove(lines, #lines)
	end

	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Apply Highlights
	vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

	for _, h in ipairs(header_meta) do
		-- 1. Highlight Icon (Gray)
		vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", h.line, 0, h.icon_len)

		if h.id == "branch" then
			-- 2a. Branch Special Handling
			-- " Branch: " (Heading Color) | "master" (Branch Color)
			-- Length of " Branch: " is 1 (space) + 8 ("Branch: ") = 9 chars after icon
			local split_pos = h.icon_len + 9

			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusHeading", h.line, h.icon_len, split_pos)
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusBranchName", h.line, split_pos, -1)
		else
			-- 2b. Standard Header (White/Bold)
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusHeading", h.line, h.icon_len, -1)
		end
	end

	for _, line_idx in ipairs(info_lines) do
		vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", line_idx, 0, -1)
	end
end

-- (Keep toggle_section, get_file_under_cursor, etc. exactly as they were)
function M.toggle_section(arg_heading)
	local status = require("oz.git.status")
	local current_line = arg_heading or vim.api.nvim_get_current_line()
	local icons = status.icons
	local target_section = nil

	for _, section in pairs(status.state.sections) do
		local collapsed_str = string.format("%s %s", icons.collapsed, section.header)
		local expanded_str = string.format("%s %s", icons.expanded, section.header)
		if current_line == collapsed_str or current_line == expanded_str then
			target_section = section
			break
		end
	end
	if target_section then
		target_section.collapsed = not target_section.collapsed
		local pos = vim.api.nvim_win_get_cursor(0)
		M.render(status.status_buf)
		pcall(vim.api.nvim_win_set_cursor, 0, pos)
		return true
	end
	return false
end

function M.get_file_under_cursor(fmt_origin)
	local entries = {}
	local lines = {}
	local root = require("oz.git").state.root or util.GetProjectRoot()
	if vim.api.nvim_get_mode().mode == "n" then
		table.insert(lines, vim.fn.getline("."))
	else
		local start = vim.fn.line("v")
		local end_ = vim.fn.line(".")
		lines = vim.api.nvim_buf_get_lines(0, start - 1, end_, false)
	end
	for _, line in ipairs(lines) do
		local clean_path = line:match(":%s+(.*)$") or line:match("^%s*(.*)$")
		if
			clean_path
			and not line:match("^[v>] ")
			and not line:match("^Branch:")
			and not line:match("^%s*Ahead")
			and not line:match("^%s*%[")
		then
			if not line:match("^%s*[*+]?%s+%S+%s+%x+") then
				local absolute_path = root .. "/" .. clean_path
				if vim.fn.filereadable(absolute_path) == 1 or vim.fn.isdirectory(absolute_path) == 1 then
					table.insert(entries, fmt_origin and clean_path or absolute_path)
				end
			end
		end
	end
	return entries
end

--- Get branch name under cursor
function M.get_branch_under_cursor()
    local current_line = vim.api.nvim_get_current_line()

    local header_branch = current_line:match("^[%v>%s]*Branch:%s+(%S+)")
    if header_branch then
        return header_branch
    end

    if current_line:match("^%s*[*+]?%s+%S+%s+%x+") then
        local branch_name = current_line:match("^%s*[*+]?%s+(%S+)")
        return branch_name
    end

    return nil
end

function M.get_stash_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local index, branch, name = line:match("^%s*stash@{(%d+)}:%s*On%s+(.-):%s*(.+)$")
	if index then
		return { index = tonumber(index), branch = vim.trim(branch), name = vim.trim(name) }
	end
	return {}
end

function M.run_n_refresh(cmd)
	git.after_exec_complete(function()
		vim.schedule(function()
			require("oz.git.status").refresh_buf()
		end)
	end)
	vim.cmd(cmd)
	util.inactive_echo(":" .. cmd)
end

---get section
---@return string|nil
function M.get_section_under_cursor()
	local status = require("oz.git.status")
	local state = status.state
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local current_row = 1

	for _, section_id in ipairs(status.render_order) do
		local section = state.sections[section_id]

		if section and (#section.content > 0 or section_id == "branch") then
			local start_line = current_row
			local height = 1 -- Header line

			if not section.collapsed then
				height = height + #section.content
			end

			if section_id == "branch" and state.info_lines then
				height = height + #state.info_lines
			end

			local end_line = start_line + height - 1

			if cursor_line >= start_line and cursor_line <= end_line then
				return section_id
			end

			current_row = end_line + 2
		end
	end

	return nil
end

return M
