-- inline_diff.lua
local M = {}
local util = require("oz.util")
local shell = require("oz.util.shell")
local hl_util = require("oz.util.hl")

-- ============================================================
-- Configuration & State
-- ============================================================
local ns_id = vim.api.nvim_create_namespace("oz_git_inline_diff")
local hls_setup_done = false
local expanded_diffs = {}
local last_expanded = nil

-- Efficiently setup highlights once
local function setup_highlights()
	if hls_setup_done then
		return
	end
	hl_util.setup_hls({
		{ OzGitDiffHeader = { fg = "#c678dd", bold = true } },
		{ OzGitDiffHunkHeader = { fg = "#61afef", bold = true } },
		{ OzGitDiffAdd = { fg = "#98c379", bg = "#2d3b2d" } },
		{ OzGitDiffDel = { fg = "#e06c75", bg = "#3b2d2d" } },
		{ OzGitDiffContext = { fg = "#abb2bf" } },
		{ OzGitDiffFile = { fg = "#e5c07b", bold = true } },
		{ OzGitDiffSep = { fg = "#5c6370" } },
	})
	hls_setup_done = true
end

-- ============================================================
-- Optimized Parsing
-- ============================================================
local function parse_diff(diff_text)
	if not diff_text or diff_text == "" then
		return nil
	end

	local lines = vim.split(diff_text, "\n", { plain = true })
	local result = { hunks = {} }
	local i = 1

	-- Fast-forward to first hunk
	while i <= #lines and not lines[i]:match("^@@") do
		i = i + 1
	end

	while i <= #lines do
		local line = lines[i]
		local sa, ca, sb, cb = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
		if sa then
			local hunk = {
				header = line,
				diff_start_a = tonumber(sa),
				diff_count_a = tonumber(ca) or 1,
				diff_start_b = tonumber(sb),
				diff_count_b = tonumber(cb) or 1,
				lines = {},
			}
			i = i + 1
			while i <= #lines do
				local hline = lines[i]
				if hline:match("^@@") or (hline == "" and i == #lines) then
					break
				end

				local type = "ctx"
				local char = hline:sub(1, 1)
				if char == "+" then
					type = "add"
				elseif char == "-" then
					type = "del"
				elseif char == "\\" then
					type = "info"
				end

				table.insert(hunk.lines, { type = type, text = hline })
				i = i + 1
			end
			table.insert(result.hunks, hunk)
		else
			i = i + 1
		end
	end
	return result
end

-- ============================================================
-- Optimized Line Adjustments (In-place)
-- ============================================================
function M._adjust_lines_after_insert(bufnr, after_line, count)
	local status = require("oz.git.status")
	local line_map = status.state.line_map

	local max_lnum = 0
	for lnum, _ in pairs(line_map) do
		local ln = tonumber(lnum)
		if ln and ln > max_lnum then
			max_lnum = ln
		end
	end

	for lnum = max_lnum, after_line + 1, -1 do
		if line_map[lnum] then
			line_map[lnum + count] = line_map[lnum]
			line_map[lnum] = nil
		end
	end

	local diff_marker = { type = "inline_diff" }
	for i = 1, count do
		line_map[after_line + i] = diff_marker
	end

	local buf_diffs = expanded_diffs[bufnr]
	if not buf_diffs then
		return
	end

	local to_update = {}
	for fl, info in pairs(buf_diffs) do
		if fl > after_line then
			table.insert(to_update, { old = fl, new = fl + count, info = info })
		elseif fl ~= after_line then
			if info.diff_start_line > after_line then
				info.diff_start_line = info.diff_start_line + count
				info.diff_end_line = info.diff_end_line + count
				for _, hr in pairs(info.hunk_ranges) do
					hr.start_line = hr.start_line + count
					hr.end_line = hr.end_line + count
				end
			end
		end
	end

	for _, u in ipairs(to_update) do
		buf_diffs[u.old] = nil
		u.info.diff_start_line = u.info.diff_start_line + count
		u.info.diff_end_line = u.info.diff_end_line + count
		for _, hr in pairs(u.info.hunk_ranges) do
			hr.start_line = hr.start_line + count
			hr.end_line = hr.end_line + count
		end
		buf_diffs[u.new] = u.info
	end
end

function M._adjust_lines_after_remove(bufnr, after_line, count)
	local status = require("oz.git.status")
	local line_map = status.state.line_map

	local max_lnum = 0
	for lnum, _ in pairs(line_map) do
		local ln = tonumber(lnum)
		if ln and ln > max_lnum then
			max_lnum = ln
		end
	end

	for i = 1, count do
		line_map[after_line + i] = nil
	end

	for lnum = after_line + count + 1, max_lnum do
		if line_map[lnum] then
			line_map[lnum - count] = line_map[lnum]
			line_map[lnum] = nil
		end
	end

	local buf_diffs = expanded_diffs[bufnr]
	if not buf_diffs then
		return
	end

	local to_update = {}
	for fl, info in pairs(buf_diffs) do
		if fl > after_line then
			table.insert(to_update, { old = fl, new = fl - count, info = info })
		end
	end

	for _, u in ipairs(to_update) do
		buf_diffs[u.old] = nil
		u.info.diff_start_line = u.info.diff_start_line - count
		u.info.diff_end_line = u.info.diff_end_line - count
		for _, hr in pairs(u.info.hunk_ranges) do
			hr.start_line = hr.start_line - count
			hr.end_line = hr.end_line - count
		end
		buf_diffs[u.new] = u.info
	end
end

-- ============================================================
-- CORE: Optimized Expansion
-- ============================================================

function M.toggle_inline_diff(bufnr, file_line, file_path, section, root, rel_path)
	setup_highlights()
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not expanded_diffs[bufnr] then
		expanded_diffs[bufnr] = {}
	end
	local buf_diffs = expanded_diffs[bufnr]

	if buf_diffs[file_line] then
		M.collapse_inline_diff(bufnr, file_line)
		return
	end

	M.collapse_all_diffs(bufnr)

	local status = require("oz.git.status")
	local new_file_line = nil
	for lnum, item in pairs(status.state.line_map) do
		if item.type == "file" and item.path == file_path and item.section_id == section then
			new_file_line = tonumber(lnum)
			break
		end
	end
	if not new_file_line then
		return
	end
	file_line = new_file_line

	local args = section == "staged" and { "diff", "--cached", "--no-color", "--", file_path }
		or { "diff", "--no-color", "--", file_path }
	local ok, raw_diff_tbl = shell.run_command(vim.list_extend({ "git" }, args), root)
	if not ok or #raw_diff_tbl == 0 then
		return
	end
	local raw_diff = table.concat(raw_diff_tbl, "\n")

	local parsed = parse_diff(raw_diff)
	if not parsed or #parsed.hunks == 0 then
		return
	end

	local display = build_display_lines(parsed)
	local text_lines = {}
	for _, dl in ipairs(display) do
		table.insert(text_lines, dl.text)
	end

	local was_modifiable = vim.bo[bufnr].modifiable
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, file_line, file_line, false, text_lines)

	for i, dl in ipairs(display) do
		local line_nr = file_line + i - 1
		vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_nr, 0, {
			end_row = line_nr,
			end_col = #dl.text,
			hl_group = dl.hl,
			hl_eol = true,
		})
	end
	vim.bo[bufnr].modifiable = was_modifiable

	local hunk_ranges = {}
	local current_hunk_idx = nil
	for i, dl in ipairs(display) do
		local buf_line = file_line + i
		if dl.hunk_index and dl.hunk_index ~= current_hunk_idx then
			if current_hunk_idx then
				hunk_ranges[current_hunk_idx].end_line = buf_line - 1
			end
			current_hunk_idx = dl.hunk_index
			hunk_ranges[current_hunk_idx] = {
				start_line = buf_line,
				end_line = buf_line,
				hunk_data = parsed.hunks[current_hunk_idx],
			}
		end
		if dl.hunk_index and dl.hunk_index == current_hunk_idx then
			hunk_ranges[current_hunk_idx].end_line = buf_line
		end
	end

	buf_diffs[file_line] = {
		file = file_path,
		rel_path = rel_path or file_path,
		root = root,
		section = section,
		diff_start_line = file_line + 1,
		diff_end_line = file_line + #display,
		hunk_ranges = hunk_ranges,
		display = display,
		line_count = #display,
	}

	M._adjust_lines_after_insert(bufnr, file_line, #display)
end

function build_display_lines(parsed)
	local display = {
		{
			text = "──────────────────────────────────────────",
			hl = "OzGitDiffSep",
			type = "sep",
		},
	}
	for hi, hunk in ipairs(parsed.hunks) do
		table.insert(display, { text = hunk.header, hl = "OzGitDiffHunkHeader", type = "hunk_header", hunk_index = hi })
		for li, entry in ipairs(hunk.lines) do
			local hl = entry.type == "add" and "OzGitDiffAdd"
				or (
					entry.type == "del" and "OzGitDiffDel"
					or (entry.type == "info" and "OzGitDiffSep" or "OzGitDiffContext")
				)
			table.insert(display, { text = entry.text, hl = hl, type = entry.type, hunk_index = hi, line_in_hunk = li })
		end
		if hi < #parsed.hunks then
			table.insert(
				display,
				{
					text = "── ── ── ── ── ── ── ── ── ── ── ── ── ──",
					hl = "OzGitDiffSep",
					type = "sep",
				}
			)
		end
	end
	table.insert(
		display,
		{
			text = "──────────────────────────────────────────",
			hl = "OzGitDiffSep",
			type = "sep",
		}
	)
	return display
end

function M.collapse_inline_diff(bufnr, file_line)
	local buf_diffs = expanded_diffs[bufnr]
	if not buf_diffs or not buf_diffs[file_line] then
		return
	end
	local info = buf_diffs[file_line]

	local was_modifiable = vim.bo[bufnr].modifiable
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, file_line, file_line + info.line_count, false, {})

	local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { file_line, 0 }, { file_line + info.line_count, 0 }, {})
	for _, mark in ipairs(marks) do
		vim.api.nvim_buf_del_extmark(bufnr, ns_id, mark[1])
	end

	vim.bo[bufnr].modifiable = was_modifiable
	buf_diffs[file_line] = nil
	M._adjust_lines_after_remove(bufnr, file_line, info.line_count)
end

function M.collapse_all_diffs(bufnr)
	local buf_diffs = expanded_diffs[bufnr]
	if not buf_diffs then
		return
	end
	local lines = {}
	for fl, _ in pairs(buf_diffs) do
		table.insert(lines, fl)
	end
	table.sort(lines, function(a, b)
		return a > b
	end)
	for _, fl in ipairs(lines) do
		M.collapse_inline_diff(bufnr, fl)
	end
end

-- ============================================================
-- Optimized Hunk Lookup
-- ============================================================
function M.get_hunk_at_cursor(bufnr, cursor_line)
	local buf_diffs = expanded_diffs[bufnr]
	if not buf_diffs then
		return nil
	end

	for file_line, info in pairs(buf_diffs) do
		if cursor_line >= info.diff_start_line and cursor_line <= info.diff_end_line then
			for hi, hr in pairs(info.hunk_ranges) do
				if cursor_line >= hr.start_line and cursor_line <= hr.end_line then
					local display_idx = cursor_line - file_line
					return {
						file = info.file,
						rel_path = info.rel_path,
						root = info.root,
						section = info.section,
						hunk_index = hi,
						hunk_data = hr.hunk_data,
						file_line = file_line,
						line_in_hunk = info.display[display_idx].line_in_hunk,
					}
				end
			end
			return { file = info.file, section = info.section, file_line = file_line }
		end
	end
	return nil
end

-- ============================================================
-- Surgical Patching
-- ============================================================
function M.apply_hunk_patch(hunk_info, reverse, selected_indices)
	local hd = hunk_info.hunk_data
	local patch = {
		string.format("diff --git a/%s b/%s", hunk_info.file, hunk_info.file),
		string.format("--- a/%s", hunk_info.file),
		string.format("+++ b/%s", hunk_info.file),
		hd.header,
	}

	for idx, line in ipairs(hd.lines) do
		local is_selected = true
		if selected_indices then
			is_selected = false
			for _, si in ipairs(selected_indices) do
				if si == idx then
					is_selected = true
					break
				end
			end
		end

		local type = line.type
		local text = line.text
		local content = text:sub(2)

		if type == "info" then
			table.insert(patch, text)
		elseif type == "ctx" then
			table.insert(patch, " " .. content)
		elseif reverse then
			-- UNSTAGING logic: reverse addition/deletion manually for higher reliability
			if type == "add" then
				if is_selected then
					table.insert(patch, "-" .. content) -- '+' becomes '-'
				else
					table.insert(patch, " " .. content) -- '+' becomes context
				end
			elseif type == "del" then
				if is_selected then
					table.insert(patch, "+" .. content) -- '-' becomes '+'
				else
					-- unselected deletion stays deleted. Can't be context. Omit.
				end
			end
		else
			-- STAGING logic
			if type == "add" then
				if is_selected then
					table.insert(patch, "+" .. content)
				else
					-- unselected addition stays unstaged. Omit.
				end
			elseif type == "del" then
				if is_selected then
					table.insert(patch, "-" .. content)
				else
					table.insert(patch, " " .. content) -- '-' becomes context
				end
			end
		end
	end
	table.insert(patch, "")

	-- Use standard forward apply because we manually handled the reversal
	local result = vim.system({ "git", "apply", "--cached", "--recount", "-" }, {
		stdin = table.concat(patch, "\n"),
		cwd = hunk_info.root,
		text = true,
	}):wait()

	if result.code ~= 0 then
		util.inactive_echo("Patch failed: " .. (result.stderr or "error"))
		return false
	end
	return true
end

-- ============================================================
-- UI Persistence
-- ============================================================
function M.save_state_for_line(bufnr, file_line)
	local buf_diffs = expanded_diffs[bufnr]
	if not buf_diffs or not buf_diffs[file_line] then
		return false
	end
	local info = buf_diffs[file_line]
	last_expanded = {
		file = info.file,
		section = info.section,
		root = info.root,
		rel_path = info.rel_path,
		cursor_pos = vim.api.nvim_win_get_cursor(0),
	}
	return true
end

function M.stage_hunk_at_cursor(bufnr)
	local h = M.get_hunk_at_cursor(bufnr, vim.api.nvim_win_get_cursor(0)[1])
	if not h or not h.hunk_index then
		return false
	end
	local selected = h.line_in_hunk and { h.line_in_hunk } or nil
	last_expanded = {
		file = h.file,
		section = h.section,
		root = h.root,
		rel_path = h.rel_path,
		cursor_pos = vim.api.nvim_win_get_cursor(0),
	}
	local reverse = (h.section == "staged")
	if M.apply_hunk_patch(h, reverse, selected) then
		util.inactive_echo((reverse and "Unstaged " or "Staged ") .. (selected and "line" or "hunk"))
		require("oz.git.status").refresh_buf()
		M.refresh_if_needed(bufnr)
	end
	return true
end

function M.stage_selection(bufnr)
	local s, e = vim.fn.line("v"), vim.fn.line(".")
	if s > e then
		s, e = e, s
	end
	local buf_diffs = expanded_diffs[bufnr]
	if not buf_diffs then
		return false
	end

	for fl, info in pairs(buf_diffs) do
		if s >= info.diff_start_line and e <= info.diff_end_line then
			for hi, hr in pairs(info.hunk_ranges) do
				if not (e < hr.start_line or s > hr.end_line) then
					local sel = {}
					for lnum = math.max(s, hr.start_line), math.min(e, hr.end_line) do
						local lih = info.display[lnum - fl].line_in_hunk
						if lih then
							table.insert(sel, lih)
						end
					end
					if #sel > 0 then
						last_expanded = {
							file = info.file,
							section = info.section,
							root = info.root,
							rel_path = info.rel_path,
							cursor_pos = vim.api.nvim_win_get_cursor(0),
						}
						util.exit_visual()
						if
							M.apply_hunk_patch(
								{ file = info.file, root = info.root, hunk_data = hr.hunk_data },
								(info.section == "staged"),
								sel
							)
						then
							util.inactive_echo("Staged selection")
							require("oz.git.status").refresh_buf()
							M.refresh_if_needed(bufnr)
						end
						return true
					end
				end
			end
		end
	end
	return false
end

function M.refresh_if_needed(bufnr)
	if not last_expanded then
		return
	end
	expanded_diffs[bufnr] = {}
	local status = require("oz.git.status")
	local new_l, new_s = nil, nil
	for lnum, item in pairs(status.state.line_map) do
		if item.type == "file" and item.path == last_expanded.file then
			new_l, new_s = tonumber(lnum), item.section_id
			if new_s == last_expanded.section then
				break
			end
		end
	end
	if new_l then
		M.toggle_inline_diff(bufnr, new_l, last_expanded.file, new_s, last_expanded.root, last_expanded.rel_path)
		pcall(vim.api.nvim_win_set_cursor, 0, last_expanded.cursor_pos)
	end
	last_expanded = nil
end

function M.cleanup(bufnr)
    if expanded_diffs[bufnr] then expanded_diffs[bufnr] = nil end
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

return M
