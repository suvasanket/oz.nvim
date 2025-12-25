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
    for _, w in ipairs(worktree_meta) do
        local is_prunable = w.content:match("%(prunable%)")

        if is_prunable then
            vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", w.line, 0, -1)
            local p_start, p_end = w.content:find("prunable")
            if p_start then
                vim.api.nvim_buf_add_highlight(buf, ns_id, "healthError", w.line, p_start - 1, p_end)
            end
        else
            -- 1. Name: Start of text until '('
            local name_start = w.content:find("%S")
            local b_open = w.content:find("%(", name_start or 0)

            if name_start and b_open then
                -- Highlight Name (Directory Color)
                vim.api.nvim_buf_add_highlight(buf, ns_id, "Directory", w.line, name_start - 1, b_open - 1)

                -- 2. Branch: Inside ()
                local b_close = w.content:find("%)", b_open)
                if b_close then
                    -- Highlight Branch (excluding parens)
                    vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusBranchName", w.line, b_open, b_close - 1)

                    -- 3. SHA: First hex string after ')'
                    local sha_start, sha_end = w.content:find("%x+", b_close + 1)
                    if sha_start then
                        vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", w.line, sha_start - 1, sha_end)
                    end
                end
            end
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
			if cursor_line == current_row then
				return section_id
			end
			local height = 1
			if not section.collapsed then
				height = height + #section.content
			end
			if section_id == "branch" and state.info_lines then
				height = height + #state.info_lines
			end
			current_row = current_row + height + 1
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
		if not line:match("^%s*$") then
			local clean_path = line:match(":%s+(.*)$") or line:match("^%s*(.*)$")
			if clean_path and clean_path ~= "" then
				local is_worktree = line:match("^[v" .. require("oz.git.status").icons.collapsed .. "]")
					or line:match("^(.*)%s+/%S+")
				local is_header = line:match("^[v" .. require("oz.git.status").icons.collapsed .. "] ")
				local is_branch = line:match("^Branch:") or line:match("^%s*[*+]?%s+%S+%s+%x+")
				local is_stash = line:match("^%s*stash@")
				local is_info = line:match("^%s*Ahead") or line:match("^%s*%[")
				-- WT Line format:  [branch] name sha
				local is_wt_line = line:match("%[.*%]%s+%S+%s+%x+")

				if
					not is_header
					and not is_branch
					and not is_info
					and not is_worktree
					and not is_stash
					and not is_wt_line
				then
					local absolute_path = root .. "/" .. clean_path
					if absolute_path ~= root .. "/" then
						if vim.fn.filereadable(absolute_path) == 1 or vim.fn.isdirectory(absolute_path) == 1 then
							table.insert(entries, fmt_origin and clean_path or absolute_path)
						end
					end
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
	-- Format:  [branch]  name  sha  ...

	local branch_part, name, sha = line:match("^%s*(%S+)%s+(%S+)%s+(%x+)")

	if branch_part and name and sha then
		local branch = branch_part:match("%[(.-)%]") or "HEAD"
		-- Note: path here is just the name (e.g. "feature-1")
		return {
			path = name,
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
