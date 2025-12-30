local M = {}
local util = require("oz.util")
local git = require("oz.git")

local status_code_map = {
	["M"] = "modified:   ",
	["A"] = "new file:   ",
	["D"] = "deleted:    ",
	["R"] = "renamed:    ",
	["C"] = "copied:     ",
	["U"] = "unmerged:   ",
	["?"] = "",
}

-- Render the buffer based on M.state
function M.render(buf)
	local status = require("oz.git.status")
	local state = status.state
	local order = status.render_order
	local ns_id = vim.api.nvim_create_namespace("oz_git_status_icons")

	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	-- Reset map and signs
	state.line_map = {}
	vim.fn.sign_unplace("oz_git_status_signs", { buffer = buf })

	local lines = {}
	local signs_to_place = {}

	-- Helper to add line and map
	local function add_line(text, data)
		table.insert(lines, text)
		state.line_map[#lines] = data
	end

	for _, section_id in ipairs(order) do
		local section = state.sections[section_id]
		if section and (#section.content > 0 or section_id == "branch") then
			-- 1. Header
			local sign_name = section.collapsed and "OzGitStatusCollapsed" or "OzGitStatusExpanded"
			-- Next line index is #lines + 1
			local line_idx = #lines + 1
			table.insert(signs_to_place, { name = sign_name, lnum = line_idx })
			add_line(section.header, { type = "header", section_id = section_id })

			-- 2. Content
			if not section.collapsed then
				for _, item in ipairs(section.content) do
					local item_data = vim.deepcopy(item)
					item_data.section_id = section_id

					if item.type == "file" then
						local prefix = status_code_map[item.status] or "modified:   "
						add_line("  " .. prefix .. item.path, item_data)
					elseif item.type == "branch_item" then
						add_line(item.text, item_data)
					elseif item.type == "worktree" then
						local display = string.format("  %s(%s) %s %s", item.name, item.branch, item.sha, item.status)
						display = display:gsub("%s+$", "")
						add_line(display, item_data)
					elseif item.type == "stash" then
						add_line(item.raw, item_data)
					end
				end
			end

			-- 3. Info Line (Only for branch)
			if section_id == "branch" and state.info_lines and #state.info_lines > 0 then
				for _, info in ipairs(state.info_lines) do
					add_line("  " .. info, { type = "info", text = info, section_id = section_id })
				end
			end

			-- Spacer
			add_line("", { type = "spacer" })
		end
	end

	-- Remove last spacer if exists
	if lines[#lines] == "" then
		table.remove(lines, #lines)
		state.line_map[#lines + 1] = nil -- Clear map for removed line
	end

	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Place Signs
	for _, sign in ipairs(signs_to_place) do
		vim.fn.sign_place(0, "oz_git_status_signs", sign.name, buf, { lnum = sign.lnum, priority = 10 })
	end

	-- Apply Highlights
	vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

	for lnum, data in pairs(state.line_map) do
		local row = lnum - 1 -- 0-based
		if data.type == "header" then
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusHeading", row, 0, -1)
			if data.section_id == "branch" then
				-- Highlight branch name if present in header
				-- "Branch: master"
				local b_name = lines[lnum]:match("Branch:%s+(.*)")
				if b_name then
					local start = lines[lnum]:find(b_name, 1, true)
					if start then
						vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusBranchName", row, start - 1, -1)
					end
				end
			end
		elseif data.type == "info" then
			vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", row, 0, -1)
		elseif data.type == "worktree" then
			-- Re-implement worktree highlighting logic
			local line_text = lines[lnum]
			local is_prunable = line_text:match("%(prunable%)")
			if is_prunable then
				vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", row, 0, -1)
				local p_start, p_end = line_text:find("prunable")
				if p_start then
					vim.api.nvim_buf_add_highlight(buf, ns_id, "healthError", row, p_start - 1, p_end)
				end
			else
				local name_start = line_text:find("%S")
				local b_open = line_text:find("%(", name_start or 0)
				if name_start and b_open then
					vim.api.nvim_buf_add_highlight(buf, ns_id, "Directory", row, name_start - 1, b_open - 1)
					local b_close = line_text:find("%)", b_open)
					if b_close then
						vim.api.nvim_buf_add_highlight(buf, ns_id, "ozGitStatusBranchName", row, b_open, b_close - 1)
						local sha_start, sha_end = line_text:find("%x+", b_close + 1)
						if sha_start then
							vim.api.nvim_buf_add_highlight(buf, ns_id, "ozInactivePrompt", row, sha_start - 1, sha_end)
						end
					end
				end
			end
		end
	end
end

function M.toggle_section(arg_heading)
	local status = require("oz.git.status")
	local state = status.state

	local target_section = nil

	if arg_heading then
		for _, section in pairs(state.sections) do
			if section.header == arg_heading then
				target_section = section
				break
			end
		end
	else
		local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
		local item = state.line_map[cursor_line]
		if item and item.type == "header" then
			target_section = state.sections[item.section_id]
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
	local map = status.state.line_map
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

	local item = map[cursor_line]
	if item and item.section_id then
		return item.section_id
	end
	return nil
end

function M.get_file_under_cursor(fmt_origin)
	local entries = {}
	local root = require("oz.git").state.root or util.GetProjectRoot()
	local mode = vim.api.nvim_get_mode().mode
	local start_line, end_line

	if mode == "v" or mode == "V" or mode == "" then
		start_line = vim.fn.line("v")
		end_line = vim.fn.line(".")
		if start_line > end_line then
			start_line, end_line = end_line, start_line
		end
	else
		start_line = vim.fn.line(".")
		end_line = start_line
	end

	local map = require("oz.git.status").state.line_map
	for i = start_line, end_line do
		local item = map[i]
		if item and item.type == "file" then
			local absolute_path = root .. "/" .. item.path
			if fmt_origin then
				table.insert(entries, item.path)
			else
				table.insert(entries, absolute_path)
			end
		end
	end
	return entries
end

function M.get_branch_under_cursor()
	local status = require("oz.git.status")
	local map = status.state.line_map
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local item = map[cursor_line]

	if item then
		if item.type == "header" and item.section_id == "branch" then
			return status.state.current_branch
		elseif item.type == "branch_item" then
			-- Parse branch from text: "  * master  sha msg"
			-- or "    master  sha msg"
			return item.text:match("^%s*[*+]?%s+(%S+)")
		end
	end
	return nil
end

--- Get worktree details under cursor
---@return {path:string, head:string, branch:string}|nil
function M.get_worktree_under_cursor()
	local status = require("oz.git.status")
	local map = status.state.line_map
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local item = map[cursor_line]

	if item and item.type == "worktree" then
		return {
			path = item.name,
			head = item.sha,
			branch = item.branch,
		}
	end
	return nil
end

function M.get_stash_under_cursor()
	local status = require("oz.git.status")
	local map = status.state.line_map
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local item = map[cursor_line]

	if item and item.type == "stash" and item.raw then
		local index, branch, name = item.raw:match("^%s*stash@{(%d+)}:%s*On%s+(.-):%s*(.+)$")
		if index then
			return { index = tonumber(index), branch = vim.trim(branch), name = vim.trim(name) }
		end
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

--- Jump to a section (by ID) or relative direction
---@param target any Section ID (string) or Direction (number: 1 or -1)
function M.jump_section(target)
	local status = require("oz.git.status")
	local state = status.state
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local headers = {}

	-- Identify all header lines from line_map
	for line_idx, item in pairs(state.line_map) do
		if item.type == "header" then
			table.insert(headers, line_idx)
		end
	end
	table.sort(headers)

	-- Case A: Jump to Specific ID
	if type(target) == "string" then
		for _, line in ipairs(headers) do
			if state.line_map[line].section_id == target then
				vim.api.nvim_win_set_cursor(0, { line, 0 })
				return
			end
		end
	end

	-- Case B: Jump Relative (Next/Prev)
	if type(target) == "number" and #headers > 0 then
		local dest = nil
		if target == 1 then -- Next
			for _, line in ipairs(headers) do
				if line > current_line then
					dest = line
					break
				end
			end
			if not dest then
				dest = headers[1]
			end -- Wrap to top
		elseif target == -1 then -- Prev
			for i = #headers, 1, -1 do
				if headers[i] < current_line then
					dest = headers[i]
					break
				end
			end
			if not dest then
				dest = headers[#headers]
			end -- Wrap to bottom
		end

		if dest then
			vim.api.nvim_win_set_cursor(0, { dest, 0 })
		end
	end
end

return M