local M = {}
local g_util = require("oz.git.util")

--- Run a git command and return the output.
local function git_exec(args, cwd, stdin_data)
	local cmd = { "git", "--no-pager", unpack(args) }
	local result = vim.system(cmd, {
		text = true,
		stdin = stdin_data or false,
		cwd = cwd or g_util.get_project_root(),
	}):wait()

	if result.code ~= 0 then
		return nil, string.format("git %s failed (%d):\n%s", table.concat(args, " "), result.code, result.stderr or "")
	end
	return result.stdout or ""
end

--- Get Git information for a target.
local function get_info(target, opts)
	opts = opts or {}
	if opts.root and opts.rel_path then
		return { root = opts.root, rel_path = opts.rel_path }
	end

	local filepath
	if not target or target == 0 then
		filepath = vim.api.nvim_buf_get_name(0)
	elseif type(target) == "string" then
		filepath = target
	else
		filepath = vim.api.nvim_buf_get_name(target)
	end

	if not filepath or filepath == "" then
		return nil, "No filepath provided"
	end

	local git_root = g_util.get_project_root()
	if not git_root then
		return nil, "Not a git repository"
	end

	local root_clean = git_root:gsub("/$", "")
	local abs_path = vim.fn.fnamemodify(vim.fn.resolve(filepath), ":p")
	local rel_path
	if abs_path:sub(1, #root_clean) == root_clean then
		rel_path = abs_path:sub(#root_clean + 2)
	else
		rel_path = vim.fn.fnamemodify(abs_path, ":.")
	end

	return { root = root_clean, rel_path = rel_path }
end

--------------------------------------------------------------------------------
-- Working-tree ↔ Index line mapping
--------------------------------------------------------------------------------

local function build_wt_to_index_map(root, rel_path)
	local raw = ""
	pcall(function()
		raw = git_exec({ "diff", "--no-color", "--no-ext-diff", "-U0", "--", rel_path }, root) or ""
	end)

	local hunks = {}
	for line in raw:gmatch("[^\n]+") do
		local os, oc, ns, nc = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
		if os then
			hunks[#hunks + 1] = {
				idx_start = tonumber(os),
				idx_count = tonumber(oc == "" and "1" or oc),
				wt_start = tonumber(ns),
				wt_count = tonumber(nc == "" and "1" or nc),
			}
		end
	end

	return function(wt_line)
		local offset = 0
		for _, h in ipairs(hunks) do
			local wt_end = h.wt_start + h.wt_count - 1
			if wt_line < h.wt_start then
				break
			elseif wt_line >= h.wt_start and wt_line <= wt_end then
				return h.idx_start
			else
				offset = offset + (h.idx_count - h.wt_count)
			end
		end
		return wt_line + offset
	end
end

--------------------------------------------------------------------------------
-- Diff parsing & filtering
--------------------------------------------------------------------------------

local function parse_hunk_header(header)
	local os, oc, ns, nc = header:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
	return tonumber(os), tonumber(oc == "" and "1" or oc), tonumber(ns), tonumber(nc == "" and "1" or nc)
end

local function parse_diff(raw)
	local lines = vim.split(raw, "\n", { plain = true })
	local diff = { header_lines = {}, hunks = {} }
	local i = 1

	while i <= #lines do
		if lines[i]:match("^@@") then
			break
		end
		diff.header_lines[#diff.header_lines + 1] = lines[i]
		i = i + 1
	end

	while i <= #lines do
		if lines[i]:match("^@@") then
			local hunk = { header = lines[i], lines = {} }
			i = i + 1
			while i <= #lines and not lines[i]:match("^@@") and not lines[i]:match("^diff %-%-git") do
				if i == #lines and lines[i] == "" then
					break
				end
				hunk.lines[#hunk.lines + 1] = lines[i]
				i = i + 1
			end
			diff.hunks[#diff.hunks + 1] = hunk
		else
			i = i + 1
		end
	end
	return diff
end

local function filter_hunk(hunk, sel_start, sel_end)
	local old_start, _, new_start, _ = parse_hunk_header(hunk.header)
	local out = {}
	local cur_old, cur_new = old_start, new_start

	for _, line in ipairs(hunk.lines) do
		local p = line:sub(1, 1)
		local rest = line:sub(2)

		if p == "+" then
			if cur_new >= sel_start and cur_new <= sel_end then
				out[#out + 1] = line
			end
			cur_new = cur_new + 1
		elseif p == "-" then
			if cur_new >= sel_start and cur_new <= sel_end then
				out[#out + 1] = line
			else
				out[#out + 1] = " " .. rest
			end
			cur_old = cur_old + 1
		elseif p == " " then
			out[#out + 1] = line
			cur_old, cur_new = cur_old + 1, cur_new + 1
		elseif p == "\\" then
			out[#out + 1] = line
		end
	end

	local has_diff = false
	for _, l in ipairs(out) do
		local c = l:sub(1, 1)
		if c == "+" or c == "-" then
			has_diff = true
			break
		end
	end
	if not has_diff then
		return nil
	end

	local o_count, n_count = 0, 0
	for _, l in ipairs(out) do
		local c = l:sub(1, 1)
		if c == " " then
			o_count, n_count = o_count + 1, n_count + 1
		elseif c == "-" then
			o_count = o_count + 1
		elseif c == "+" then
			n_count = n_count + 1
		end
	end

	local new_header = string.format("@@ -%d,%d +%d,%d @@", old_start, o_count, new_start, n_count)
	return new_header .. "\n" .. table.concat(out, "\n") .. "\n"
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.stage_range(target, s, e, opts)
	local info, err = get_info(target, opts)
	if not info then
		return false, err
	end

	local line_start, line_end = math.min(s, e), math.max(s, e)

	local raw_diff, diff_err = git_exec({ "diff", "--no-color", "--no-ext-diff", "-U0", "--", info.rel_path }, info.root)
	if not raw_diff or raw_diff == "" then
		return false, diff_err or "No changes to stage"
	end

	local diff = parse_diff(raw_diff)
	local patch_body = ""
	for _, hunk in ipairs(diff.hunks) do
		local filtered = filter_hunk(hunk, line_start, line_end)
		if filtered then
			patch_body = patch_body .. filtered
		end
	end

	if patch_body == "" then
		return false, string.format("No changes in range %d-%d", line_start, line_end)
	end

	local patch = table.concat(diff.header_lines, "\n") .. "\n" .. patch_body
	local _, apply_err = git_exec({ "apply", "--cached", "--unidiff-zero", "-" }, info.root, patch)
	if apply_err then
		return false, apply_err
	end

	vim.schedule(function()
		pcall(vim.cmd.checktime)
		require("oz.git").refresh_buf()
	end)
	return true
end

function M.unstage_range(target, s, e, opts)
	local info, err = get_info(target, opts)
	if not info then
		return false, err
	end

	local line_start, line_end = math.min(s, e), math.max(s, e)
	local idx_start, idx_end

	if opts and opts.is_index then
		idx_start, idx_end = line_start, line_end
	else
		local wt2idx = build_wt_to_index_map(info.root, info.rel_path)
		idx_start, idx_end = wt2idx(line_start), wt2idx(line_end)
		if idx_start > idx_end then
			idx_start, idx_end = idx_end, idx_start
		end
	end

	local raw_diff, diff_err =
		git_exec({ "diff", "--cached", "--no-color", "--no-ext-diff", "-U0", "--", info.rel_path }, info.root)
	if not raw_diff or raw_diff == "" then
		return false, diff_err or "No staged changes to unstage"
	end

	local diff = parse_diff(raw_diff)
	local patch_body = ""
	for _, hunk in ipairs(diff.hunks) do
		local filtered = filter_hunk(hunk, idx_start, idx_end)
		if filtered then
			patch_body = patch_body .. filtered
		end
	end

	if patch_body == "" then
		return false, string.format("No staged changes in index range %d-%d", idx_start, idx_end)
	end

	local patch = table.concat(diff.header_lines, "\n") .. "\n" .. patch_body
	local _, apply_err = git_exec({ "apply", "--cached", "--reverse", "--unidiff-zero", "-" }, info.root, patch)
	if apply_err then
		return false, apply_err
	end

	vim.schedule(function()
		pcall(vim.cmd.checktime)
		require("oz.git").refresh_buf()
	end)
	return true
end

return M
