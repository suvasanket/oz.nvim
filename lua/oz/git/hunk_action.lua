local M = {}
local g_util = require("oz.git.util")

local function run_git(args, cwd, input)
	local cmd = { "git", "-C", cwd, "--no-pager" }
	vim.list_extend(cmd, args)

	local output = vim.fn.systemlist(cmd, input)
	if vim.v.shell_error ~= 0 then
		return nil, table.concat(output, "\n")
	end
	return output
end

local function get_git_info(bufnr, opts)
	opts = opts or {}
	bufnr = bufnr or 0

	-- If explicit paths provided, use them
	if opts.root and opts.rel_path then
		return {
			root = opts.root,
			rel_path = opts.rel_path,
		}
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		return nil, "Buffer has no filepath"
	end

	filepath = vim.fn.resolve(filepath)
	local cwd = vim.fn.fnamemodify(filepath, ":h")

	local git_root = g_util.get_project_root()
	if not git_root then
		return nil, "Not a git repository"
	end

	local rel_path = filepath:sub(#git_root + 2) -- +2 for trailing slash

	return {
		root = git_root,
		rel_path = rel_path,
		cwd = cwd,
	}
end

-- Parses the diff and extracts changes strictly within start_line and end_line
local function generate_patch(diff_lines, start_line, end_line)
	local file_headers = {}
	local patch_content = {}
	local has_matches = false

	local i = 1

	-- 1. Capture Git File Headers (lines before first @@)
	while i <= #diff_lines do
		if diff_lines[i]:match("^@@") then
			break
		end
		table.insert(file_headers, diff_lines[i])
		i = i + 1
	end

	-- 2. Iterate Hunks
	while i <= #diff_lines do
		local line = diff_lines[i]

		if line:match("^@@") then
			-- Parse Header: @@ -OldStart,OldCount +NewStart,NewCount @@
			local old_str, new_str = line:match("^@@ %-(.+) %+(.+) @@")

			local function parse_nums(s)
				local s_start, s_count = s:match("(%d+),(%d+)")
				if not s_start then
					s_start = s
					s_count = 1
				end
				return tonumber(s_start), tonumber(s_count)
			end

			local hunk_old_start, _ = parse_nums(old_str)
			local hunk_new_start, _ = parse_nums(new_str)

			local current_new_line = hunk_new_start
			local current_old_line = hunk_old_start

			-- State for capturing sub-hunks
			local sub_body = {}
			local pending_deletions = {}
			local capture_new_start = nil
			local capture_old_start = nil
			local capture_add_count = 0
			local capture_del_count = 0

			i = i + 1 -- Enter Hunk Body

			while i <= #diff_lines do
				local content = diff_lines[i]
				if not content or content:match("^@@") then
					break
				end -- Next hunk detected

				local char = content:sub(1, 1)

				if char == "-" then
					-- Deletions are queued and attached to the *next* addition
					table.insert(pending_deletions, content)
					current_old_line = current_old_line + 1
				elseif char == "+" then
					-- Check if this added line is within the user's requested range
					if current_new_line >= start_line and current_new_line <= end_line then
						has_matches = true

						-- Start a new capture block if needed
						if not capture_new_start then
							capture_new_start = current_new_line
							capture_old_start = current_old_line - #pending_deletions
						end

						-- Flush pending deletions (modification case)
						for _, del in ipairs(pending_deletions) do
							table.insert(sub_body, del)
							capture_del_count = capture_del_count + 1
						end

						pending_deletions = {}

						-- Add current line
						table.insert(sub_body, content)
						capture_add_count = capture_add_count + 1
					else
						-- Outside range. If we were capturing, close the block.
						if capture_new_start then
							local header = string.format(
								"@@ -%d,%d +%d,%d @@",
								capture_old_start,
								capture_del_count,
								capture_new_start,
								capture_add_count
							)
							table.insert(patch_content, header)
							for _, l in ipairs(sub_body) do
								table.insert(patch_content, l)
							end

							sub_body = {}
							capture_new_start = nil
							capture_add_count = 0
							capture_del_count = 0
						end
						-- Discard pending deletions as they don't belong to a selected line
						pending_deletions = {}
					end
					current_new_line = current_new_line + 1
				elseif char == "\\" then
					-- Handle "No newline at end of file"
					if capture_new_start then
						table.insert(sub_body, content)
					end
				end
				i = i + 1
			end

			-- End of Hunk: Flush remaining capture
			if capture_new_start and #sub_body > 0 then
				local header = string.format(
					"@@ -%d,%d +%d,%d @@",
					capture_old_start,
					capture_del_count,
					capture_new_start,
					capture_add_count
				)
				table.insert(patch_content, header)
				for _, l in ipairs(sub_body) do
					table.insert(patch_content, l)
				end
			end
		else
			i = i + 1
		end
	end

	if not has_matches then
		return nil
	end
	return table.concat(file_headers, "\n") .. "\n" .. table.concat(patch_content, "\n") .. "\n"
end

local function apply_operation(op, bufnr, start_line, end_line, opts)
	bufnr = bufnr or 0
	local info, err = get_git_info(bufnr, opts)
	if not info then
		return false, err
	end

	-- Normalize range
	local s = math.min(start_line, end_line)
	local e = math.max(start_line, end_line)

	-- 1. Diff
	local diff_args = { "diff", "--no-color", "--no-ext-diff", "-U0", "--", info.rel_path }
	if op == "unstage" then
		table.insert(diff_args, 2, "--cached")
	end

	local diff_lines, diff_err = run_git(diff_args, info.root)
	if not diff_lines or #diff_lines == 0 then
		return false, (diff_err or ("No changes found to " .. op))
	end

	-- 2. Construct Patch
	local patch = generate_patch(diff_lines, s, e)
	if not patch then
		return false, "No changes found specifically in range " .. s .. "-" .. e
	end

	-- 3. Apply
	local apply_args = { "apply", "--unidiff-zero", "--whitespace=nowarn" }
	if op == "stage" then
		table.insert(apply_args, 2, "--cached")
	elseif op == "unstage" then
		table.insert(apply_args, 2, "--cached")
		table.insert(apply_args, "--reverse")
	elseif op == "restore" then
		table.insert(apply_args, "--reverse")
	end
	table.insert(apply_args, "-")

	local _, apply_err = run_git(apply_args, info.root, patch)

	if apply_err then
		return false, apply_err
	end

	-- Reload buffer to sync with disk if it's the current file
	if bufnr == 0 or bufnr == vim.api.nvim_get_current_buf() then
		vim.api.nvim_command("checktime")
	end

	return true, nil
end

---
--- Stage lines in range
---@param bufnr number|nil Buffer number (0 for current)
---@param start_line number Start line number (1-based)
---@param end_line number End line number (1-based)
---@param opts table|nil Optional overrides {root=..., rel_path=...}
---@return boolean success
---@return string|nil error_message
function M.stage_range(bufnr, start_line, end_line, opts)
	return apply_operation("stage", bufnr, start_line, end_line, opts)
end

---
--- Unstage lines in range
---@param bufnr number|nil Buffer number (0 for current)
---@param start_line number Start line number (1-based)
---@param end_line number End line number (1-based)
---@param opts table|nil Optional overrides {root=..., rel_path=...}
---@return boolean success
---@return string|nil error_message
function M.unstage_range(bufnr, start_line, end_line, opts)
	return apply_operation("unstage", bufnr, start_line, end_line, opts)
end

---
--- Restore lines in range (discard changes in working tree)
---@param bufnr number|nil Buffer number (0 for current)
---@param start_line number Start line number (1-based)
---@param end_line number End line number (1-based)
---@param opts table|nil Optional overrides {root=..., rel_path=...}
---@return boolean success
---@return string|nil error_message
function M.restore_range(bufnr, start_line, end_line, opts)
	return apply_operation("restore", bufnr, start_line, end_line, opts)
end

return M
