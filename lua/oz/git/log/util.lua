local M = {}
local util = require("oz.util")
local git = require("oz.git")

local op_to_marker = {
	bisect = ">",
	["cherry-pick"] = "C",
	merge = "M",
	rebase = "R",
}

-- Run git command and refresh log buffer
function M.run_n_refresh(cmd)
	git.on_job_exit("log_refresh", {
		once = true,
		callback = function()
			vim.schedule(function()
				require("oz.git.log").refresh_buf()
			end)
		end,
	})
	util.setup_hls({ "OzCmdPrompt" })
	vim.api.nvim_echo({ { ":" .. cmd, "OzCmdPrompt" } }, false, {})
	vim.cmd(cmd)
end

-- Clear all picked hashes
function M.clear_all_picked()
	local log = require("oz.git.log")
	local grab_hashs = log.grab_hashs
	util.stop_monitoring(grab_hashs)

	-- Clear the table in-place
	for k in pairs(grab_hashs) do
		grab_hashs[k] = nil
	end
	while #grab_hashs > 0 do
		table.remove(grab_hashs)
	end

	vim.api.nvim_echo({ { "" } }, false, {})
	log.refresh_buf(true)
end

-- Execute callback with current commit hash
function M.cmd_upon_current_commit(callback)
	local hash = M.get_selected_hash()
	if #hash > 0 then
		callback(hash[1])
	end
end

-- get selected or current SHA under cursor
---@return table
function M.get_selected_hash()
	local lines = {}
	local entries = {}
	if vim.api.nvim_get_mode().mode == "n" then
		local line = vim.fn.getline(".")
		table.insert(lines, line)
	else
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	end

	for _, line in ipairs(lines) do
		for hash in line:gmatch("[0-9a-f]%w[0-9a-f]%w[0-9a-f]%w[0-9a-f]+") do
			if #hash >= 7 and #hash <= 40 then
				util.tbl_insert(entries, hash)
			end
		end
	end

	if vim.api.nvim_get_mode().mode == "n" then
		return { entries[1] }
	end
	return entries
end

function M.apply_log_highlights(buf_id, raw_lines, git_state, log_win)
	if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then return end

	util.setup_ansi_hls()
	util.setup_hls({ "OzEchoDef", "OzActive" })

	local sl = vim.api.nvim_get_hl(0, { name = "StatusLine", link = false })
	local sl_bg = sl.bg or sl.background or "NONE"
	vim.api.nvim_set_hl(0, "OzGitLogRef", { fg = sl_bg, bg = sl_bg })

	local marker = git_state and op_to_marker[git_state.operation] or nil
	local grab_hashs = require("oz.git.log").grab_hashs
	local is_bisecting = git_state and git_state.operation == "bisect"
	local marker_width = (marker or is_bisecting or #grab_hashs > 0) and 2 or 0

	-- Set Winbar if operation is active
	if marker and log_win and vim.api.nvim_win_is_valid(log_win) then
		local op_name = git_state.operation:gsub("^%l", string.upper)
		local winbar_text = string.format(" %s (%%#OzActive#%s%%#Normal#) %%*", op_name, marker)
		vim.api.nvim_set_option_value("winbar", winbar_text, { win = log_win })
	elseif log_win and vim.api.nvim_win_is_valid(log_win) then
		vim.api.nvim_set_option_value("winbar", "", { win = log_win })
	end

	local stripped_lines, highlights = util.parse_ansi(raw_lines)
	local hl_cache = {}
	local final_lines, final_highlights = {}, {}
	local sha_width = 8
	local ns_id = vim.api.nvim_create_namespace("OzGitLogAnsi")

	for i, line in ipairs(stripped_lines) do
		local line_idx = i - 1
		local author, date
		local main_part, a, d = line:match("(.*) AUTHOR:(.*) DATE:(.*)")
		if main_part then line, author, date = main_part, a, d end

		local s, e = line:find("[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+")
		local prefix = s and line:sub(1, s - 1) or ""
		local is_header = s and (prefix == "" or prefix:match("^[|*\\/_ %-%.+=<>]+$"))
		local new_line

		if is_header then
			local sha = line:sub(s, e)
			local rest = line:sub(e + 1)
			local decor = rest:match("^ %b()") or ""
			local marker_char = prefix:match("[+=<>%-]") or " "
			local graph = prefix:gsub("[+=<>%-]", "")

			local final_marker = " "
			local marker_hl = "OzActive"

			if git_state and git_state.operation == "bisect" then
				local b_marker = git_state.bisect_map and git_state.bisect_map[sha:sub(1, 7)]
				if b_marker == "B" then
					final_marker = "B"
					marker_hl = "DiagnosticError"
				elseif b_marker == "G" then
					final_marker = "G"
					marker_hl = "DiagnosticOk"
				elseif b_marker == "S" then
					final_marker = "S"
                    marker_hl = "DiagnosticInfo"
				elseif git_state.hash and sha:find("^" .. git_state.hash) then
					final_marker = ">"
					marker_hl = "OzActive"
				end
			end

			if final_marker == " " then
				if git_state and git_state.hash and sha:find("^" .. git_state.hash) then
					final_marker = marker or ">"
					marker_hl = "OzActive"
				elseif marker_char == "=" then
					final_marker = "C"
					marker_hl = "OzActive"
				end
			end

			for _, h in ipairs(grab_hashs) do
				if h:find("^" .. sha) or sha:find("^" .. h) then
					final_marker = "C"
					marker_hl = "OzActive"
					break
				end
			end

			local padded_sha = sha .. string.rep(" ", math.max(0, sha_width - #sha))
			local padded_marker = marker_width > 0 and (final_marker .. string.rep(" ", marker_width - #final_marker)) or ""
			new_line = padded_marker .. padded_sha .. " " .. graph .. rest

			local b_s, b_e = new_line:find(" %b()", marker_width + sha_width + 1)
			local inside_s, inside_e = b_s and b_s + 1 or nil, b_s and b_e - 1 or nil

			for _, hl in ipairs(highlights) do
				if hl[1] == line_idx then
					local h_s, h_e = hl[2], hl[3]
					local n_s, n_e
					if h_s >= s - 1 and h_e <= e then
						n_s, n_e = h_s - (s - 1) + marker_width, h_e - (s - 1) + marker_width
					elseif h_e <= s - 1 then
						n_s, n_e = h_s + marker_width + sha_width + 1, h_e + marker_width + sha_width + 1
					else
						local shift = (marker_width + sha_width + 1 + #graph) - e
						n_s, n_e = h_s + shift, h_e + shift
					end

					if b_s and n_s >= inside_s and n_e <= inside_e then
						local cached_name = hl[4] .. "_Blended"
						if not hl_cache[cached_name] then
							local base = vim.api.nvim_get_hl(0, { name = hl[4], link = true })
							vim.api.nvim_set_hl(0, cached_name, { fg = base.fg, bg = sl_bg, bold = base.bold, italic = base.italic })
							hl_cache[cached_name] = true
						end
						table.insert(final_highlights, { line_idx, n_s, n_e, cached_name, 150 })
					else
						table.insert(final_highlights, { line_idx, n_s, n_e, hl[4], 100 })
					end
				end
			end
			table.insert(final_highlights, { line_idx, marker_width, marker_width + #sha, "OzEchoDef", 120 })
			if marker_width > 0 and final_marker ~= " " then
				table.insert(final_highlights, { line_idx, 0, 1, marker_hl, 160 })
			end
			if b_s then table.insert(final_highlights, { line_idx, b_s, b_e, "OzGitLogRef", 140 }) end
		else
			new_line = string.rep(" ", marker_width + sha_width + 1) .. line
			local b_s, b_e = new_line:find(" %b()", marker_width + sha_width + 1)
			for _, hl in ipairs(highlights) do
				if hl[1] == line_idx then
					local n_s, n_e = hl[2] + marker_width + sha_width + 1, hl[3] + marker_width + sha_width + 1
					table.insert(final_highlights, { line_idx, n_s, n_e, hl[4], 100 })
				end
			end
			if b_s then table.insert(final_highlights, { line_idx, b_s, b_e, "OzGitLogRef", 140 }) end
		end

		-- Node Highlight (*)
		local node_idx = new_line:find("*", marker_width + sha_width)
		if node_idx then
			table.insert(final_highlights, { line_idx, node_idx - 1, node_idx, "OzEchoDef", 110 })
		end

		if author and date then
			local a = vim.trim(author):sub(1, 18)
			local d = vim.trim(date):sub(1, 14)
			table.insert(final_highlights, {
				line_idx, 0, 0, "OzEchoDef", 200,
				{
					virt_text = {
						{ a .. string.rep(" ", 18 - #a), "OzEchoDef" },
						{ "   ", "None" },
						{ d .. string.rep(" ", 14 - #d), "OzEchoDef" },
						{ "  ", "None" },
					},
					virt_text_pos = "right_align",
				},
			})
		end
		table.insert(final_lines, new_line)
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, final_lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
	for _, hl in ipairs(final_highlights) do
		local opts = { end_col = hl[3] ~= 0 and hl[3] or nil, hl_group = hl[4], priority = hl[5] }
		if hl[6] then opts = vim.tbl_extend("force", opts, hl[6]) end
		pcall(vim.api.nvim_buf_set_extmark, buf_id, ns_id, hl[1], hl[2], opts)
	end
	vim.cmd("syntax clear")
end

function M.generate_content(level, cwd, user_set_args, original_cwd)
	local fmt
	if level == 2 then
		fmt = "format:%C(auto)%m%h%d AUTHOR:%an DATE:%aD (%ar)%n%C(reset)%s"
	elseif level == 3 then
		fmt = "format:%C(auto)%m%h%d %C(reset)%s%n          %C(dim)%an <%ae>%n          %ar [%ad]%C(reset)"
	else
		fmt = "format:%C(auto)%m%h%d %C(reset)%s AUTHOR:%an DATE:%ar"
	end

	local base_args = { "git", "log", "--graph", "--abbrev-commit", "--decorate", "--cherry-mark", "--color=always", "--format=" .. fmt }
	local final_args = {}
	for _, v in ipairs(base_args) do table.insert(final_args, v) end

	local input_args = user_set_args or { "--all" }
	local has_all = false
	local has_ref = false
	local files = {}
	local other_args = {}
	local in_files = false

	for _, arg in ipairs(input_args) do
		if in_files then
			table.insert(files, arg)
		elseif arg == "--" then
			in_files = true
		elseif arg == "--all" then
			has_all = true
			table.insert(other_args, arg)
		elseif arg:sub(1, 1) == "-" then
			table.insert(other_args, arg)
		else
			-- Check if it's a ref or a file
			-- If it contains / or . or exists on disk relative to original_cwd, it's likely a file
			local full_path = original_cwd and (original_cwd .. "/" .. arg) or arg
			if arg:find("/") or arg:find("%.", 1, true) or vim.fn.filereadable(full_path) == 1 or vim.fn.isdirectory(full_path) == 1 then
				table.insert(files, arg)
			else
				local is_ref = vim.fn.system("git rev-parse --verify " .. vim.fn.shellescape(arg) .. " 2>/dev/null") ~= ""
				if is_ref then
					has_ref = true
					table.insert(other_args, arg)
				else
					table.insert(files, arg)
				end
			end
		end
	end

	-- Resolve file paths relative to git root (cwd)
	if #files > 0 and original_cwd and original_cwd ~= cwd then
		local resolved_files = {}
		for _, f in ipairs(files) do
			-- Join original_cwd with f to get absolute path
			local abs = original_cwd .. "/" .. f
			-- Normalize it
			abs = vim.fn.fnamemodify(abs, ":p")
			-- Now make it relative to the git root (cwd)
			-- We need to temporarily set the CWD to the git root so fnamemodify(:.) works
			local rel
			local saved_cwd = vim.fn.getcwd()
			vim.cmd("lcd " .. cwd)
			rel = vim.fn.fnamemodify(abs, ":.")
			vim.cmd("lcd " .. saved_cwd)
			table.insert(resolved_files, rel)
		end
		files = resolved_files
	end

	-- If no explicit ref is provided, and we have files, default to --all to show history everywhere
	if not has_ref and not has_all and #files > 0 then
		table.insert(final_args, "--all")
	elseif not has_ref and not has_all and #other_args == 0 then
		table.insert(final_args, "--all")
	end

	-- Add other flags/refs
	for _, arg in ipairs(other_args) do
		if arg ~= "--all" or not vim.tbl_contains(final_args, "--all") then
			table.insert(final_args, arg)
		end
	end

	-- If exactly one file is provided, add --follow to see renames
	if #files == 1 then
		table.insert(final_args, "--follow")
	end

	-- Add files at the end with -- separator
	if #files > 0 then
		table.insert(final_args, "--")
		for _, f in ipairs(files) do
			table.insert(final_args, f)
		end
	end

	local ok, content = util.run_command(final_args, cwd)
	return ok and content or {}
end

return M
