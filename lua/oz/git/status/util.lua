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
	local worktree_meta = {}
	local info_lines = {}

	for _, section_id in ipairs(order) do
		local section = state.sections[section_id]

		-- Logic: Always show branch section. For others, only show if content > 0.
		if section and (#section.content > 0 or section_id == "branch") then
			-- 1. Header
			local icon = section.collapsed and icons.collapsed or icons.expanded
			local display_header = string.format("%s %s", icon, section.header)
			table.insert(lines, display_header)
			table.insert(header_meta, { line = #lines - 1, icon_len = #icon, id = section_id })

			-- 2. Content
			if not section.collapsed then
				for _, line in ipairs(section.content) do
					table.insert(lines, line)
					if section_id == "worktrees" then
						table.insert(worktree_meta, { line = #lines - 1, content = line })
					end
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

	-- Headers
	for _, h in ipairs(header_meta) do
		vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", h.line, 0, h.icon_len)
		if h.id == "branch" then
			local split_pos = h.icon_len + 9
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusHeading", h.line, h.icon_len, split_pos)
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusBranchName", h.line, split_pos, -1)
		else
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusHeading", h.line, h.icon_len, -1)
		end
	end

	-- Info Lines
	for _, line_idx in ipairs(info_lines) do
		vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", line_idx, 0, -1)
	end

	-- Worktree Specific Highlighting
	-- Format:   /path/to/worktree  sha [branch]
	for _, w in ipairs(worktree_meta) do
		local path_part = w.content:match("^(.-)%s+%x+")
		if path_part then
			local last_slash_next_idx = path_part:match(".*()/")
			if last_slash_next_idx then
				vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", w.line, 0, last_slash_next_idx - 1)
			end
		end

		-- 2. SHA (Gray)
		local sha_start, sha_end = w.content:find("%s+(%x+)%s+")
		if sha_start then
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", w.line, sha_start, sha_end)
		end

		-- 3. Branch (Color, excluding brackets)
		local b_open = w.content:find("%[", sha_end or 0)
		local b_close = w.content:find("%]", b_open or 0)

		if b_open and b_close then
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusBranchName", w.line, b_open, b_close - 1)
		end
	end
end

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

function M.get_section_under_cursor()
	local status = require("oz.git.status")
	local state = status.state
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local current_row = 1
	for _, section_id in ipairs(status.render_order) do
		local section = state.sections[section_id]
		if section and (#section.content > 0 or section_id == "branch") then
			local start_line = current_row
			local height = 1
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
		local is_worktree = line:match("^%s*/") or line:match("^%s*[%w_/-]+%s+%x+%s+%[")
		if
			clean_path
			and not line:match("^[v" .. require("oz.git.status").icons.collapsed .. "] ")
			and not line:match("^Branch:")
			and not line:match("^%s*Ahead")
			and not line:match("^%s*%[")
			and not is_worktree
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

function M.get_branch_under_cursor()
	local current_line = vim.api.nvim_get_current_line()
	local header_branch =
		current_line:match("^[%v" .. require("oz.git.status").icons.collapsed .. "%s]*Branch:%s+(%S+)")
	if header_branch then
		return header_branch
	end
	if current_line:match("^%s*[*+]?%s+%S+%s+%x+") then
		return current_line:match("^%s*[*+]?%s+(%S+)")
	end
	return nil
end

--- Get worktree details under cursor
---@return {path:string, head:string, branch:string}|nil
function M.get_worktree_under_cursor()
	local line = vim.api.nvim_get_current_line()
	-- Format:   /path/to/worktree  sha [branch]
	local path, sha, branch = line:match("^%s*(%S+)%s+(%x+)%s+%[(.-)%]$")

	if path and sha and branch then
		return {
			path = path,
			head = sha,
			branch = branch,
		}
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

return M
