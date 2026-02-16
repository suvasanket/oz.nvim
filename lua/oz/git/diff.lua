local M = {}
local util = require("oz.util")
local shell = require("oz.util.shell")
local oz_git_win = require("oz.git.oz_git_win")
local git_util = require("oz.git.util")

local function get_content(target)
	local state = require("oz.git").state
	state.show_cache = state.show_cache or {}
	if state.show_cache[target] then
		return state.show_cache[target]
	end
	local ok, content = shell.run_command({ "git", "show", target })
	if ok then
		state.show_cache[target] = content
		return content
	end
	return { "" }
end

local function fallback_text(args)
	local ok, lines = shell.run_command({ "git", "diff", unpack(args) })
	if ok then
		oz_git_win.open_oz_git_win(lines, "diff " .. table.concat(args, " "))
		vim.api.nvim_set_option_value("filetype", "diff", { buf = 0 })
	end
end

local start_visual_diff -- forward decl

local function show_picker(files, args)
	local choices = vim.deepcopy(files)
	table.insert(choices, 1, "[ALL] (Text Summary)")
	vim.ui.select(choices, { prompt = "Select File to Diff:" }, function(choice)
		if not choice then
			return
		end
		if choice == "[ALL] (Text Summary)" then
			fallback_text(args)
		else
			local idx = 0
			for i, f in ipairs(files) do
				if f == choice then
					idx = i
					break
				end
			end
			start_visual_diff(choice, args, files, idx)
		end
	end)
end

local function setup_diff_buf(buf, name, content, ft)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	pcall(vim.api.nvim_buf_set_name, buf, name)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	if ft then
		vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
	end
end

function start_visual_diff(target_file, args, file_list, index)
	local root = git_util.get_project_root()
	if not root then
		return fallback_text(args)
	end

	local abs_target =
		vim.fs.normalize(vim.startswith(target_file, "/") and target_file or (root .. "/" .. target_file))
	local rel_path = abs_target:sub(#root + 2)

	-- Parse args for revisions
	local revisions = {}
	local is_cached = false
	for _, arg in ipairs(args) do
		if arg == "--cached" or arg == "--staged" then
			is_cached = true
		elseif not vim.startswith(arg, "-") and arg ~= "--" and arg ~= target_file then
			table.insert(revisions, arg)
		end
	end

	-- Determine Sides
	local lhs_name, lhs_content
	local rhs_name, rhs_content
	local rhs_is_working = false

	if #revisions == 0 then
		if is_cached then
			lhs_name, lhs_content = "HEAD", get_content("HEAD:" .. rel_path)
			rhs_name, rhs_content = "Index", get_content(":0:" .. rel_path)
		else
			lhs_name, lhs_content = "Index", get_content(":0:" .. rel_path)
			rhs_name, rhs_is_working = "Working", true
		end
	elseif #revisions == 1 then
		lhs_name, lhs_content = revisions[1], get_content(revisions[1] .. ":" .. rel_path)
		if is_cached then
			rhs_name, rhs_content = "Index", get_content(":0:" .. rel_path)
		else
			rhs_name, rhs_is_working = "Working", true
		end
	elseif #revisions >= 2 then
		lhs_name, lhs_content = revisions[1], get_content(revisions[1] .. ":" .. rel_path)
		rhs_name, rhs_content = revisions[2], get_content(revisions[2] .. ":" .. rel_path)
	end

	-- Setup View
	vim.cmd("tabnew")

	local ft = vim.filetype.match({ filename = abs_target })

	-- LHS
	local lhs_buf = vim.api.nvim_create_buf(false, true)
	setup_diff_buf(lhs_buf, lhs_name .. ":" .. rel_path, lhs_content, ft)
	vim.api.nvim_win_set_buf(0, lhs_buf)
	local lhs_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_option_value("number", true, { win = lhs_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = lhs_win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = lhs_win })
	vim.cmd("diffthis")

	-- RHS
	vim.cmd("vsplit")
	local rhs_buf
	if rhs_is_working then
		vim.cmd("edit " .. vim.fn.fnameescape(abs_target))
		rhs_buf = vim.api.nvim_get_current_buf()
	else
		rhs_buf = vim.api.nvim_create_buf(false, true)
		setup_diff_buf(rhs_buf, rhs_name .. ":" .. rel_path, rhs_content, ft)
		vim.api.nvim_win_set_buf(0, rhs_buf)
	end
	local rhs_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_option_value("number", true, { win = rhs_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = rhs_win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = rhs_win })
	vim.cmd("diffthis")

	local is_closing = false
	local function close_diff()
		if is_closing then
			return
		end
		is_closing = true
		pcall(vim.cmd, "tabclose")
	end

	local au_group = vim.api.nvim_create_augroup("OzGitDiff_" .. lhs_buf, { clear = true })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = au_group,
		pattern = { tostring(lhs_win), tostring(rhs_win) },
		callback = function()
			close_diff()
		end,
	})

	-- Helper to apply keymaps to both splits
	local function set_diff_keymaps(buf)
		local map_opts = { buffer = buf, silent = true }

		vim.keymap.set("n", "gq", close_diff, vim.tbl_extend("force", map_opts, { desc = "Close diff" }))

		local function do_hunk(op, mode)
			local s, e
			if mode == "v" then
				s = vim.fn.line("v")
				e = vim.fn.line(".")
				if s > e then
					s, e = e, s
				end
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
			else
				s = vim.fn.line(".")
				e = s
			end

			local ok, err
			if op == "stage" then
				ok, err = require("oz.git.hunk_action").stage_range(0, s, e, { root = root, rel_path = rel_path })
			else
				ok, err = require("oz.git.hunk_action").unstage_range(0, s, e, { root = root, rel_path = rel_path })
			end

			if ok then
				util.Notify((op == "stage" and "Staged" or "Unstaged") .. " lines " .. s .. "-" .. e, "info", "oz_git")
			else
				util.Notify("Failed: " .. (err or "unknown"), "error", "oz_git")
			end
		end

		vim.keymap.set("n", "gs", function()
			do_hunk("stage", "n")
		end, vim.tbl_extend("force", map_opts, { desc = "Stage hunk" }))
		vim.keymap.set("v", "gs", function()
			do_hunk("stage", "v")
		end, vim.tbl_extend("force", map_opts, { desc = "Stage selection" }))
		vim.keymap.set("n", "gu", function()
			do_hunk("unstage", "n")
		end, vim.tbl_extend("force", map_opts, { desc = "Unstage hunk" }))
		vim.keymap.set("v", "gu", function()
			do_hunk("unstage", "v")
		end, vim.tbl_extend("force", map_opts, { desc = "Unstage selection" }))

		if file_list and index then
			local function jump(dir)
				local next_idx = (index + dir - 1) % #file_list + 1
				close_diff()
				start_visual_diff(file_list[next_idx], args, file_list, next_idx)
			end

			vim.keymap.set("n", "]f", function()
				jump(1)
			end, vim.tbl_extend("force", map_opts, { desc = "Next diff file" }))

			vim.keymap.set("n", "[f", function()
				jump(-1)
			end, vim.tbl_extend("force", map_opts, { desc = "Prev diff file" }))

			vim.keymap.set("n", "<leader>f", function()
				close_diff()
				show_picker(file_list, args)
			end, vim.tbl_extend("force", map_opts, { desc = "Pick file" }))
		end

		-- Help
		vim.keymap.set("n", "g?", function()
			local leader = vim.g.mapleader or "\\"
			require("oz.util.help_keymaps").show_maps({
				group = {
					["Diff"] = { "]f", "[f", leader .. "f", "gq", "gs", "gu" },
				},
				show_general = false,
			})
		end, vim.tbl_extend("force", map_opts, { desc = "Show diff help" }))
	end

	set_diff_keymaps(lhs_buf)
	set_diff_keymaps(rhs_buf)

	util.inactive_echo("press 'g?' to see mappings.")
end

---
-- Open a diff window
---@param args table
function M.diff(args)
	require("oz.git").state.show_cache = {} -- Clear cache for new diff command
	local target_file = nil
	local dash_dash_found = false

	for _, arg in ipairs(args) do
		if arg == "--" then
			dash_dash_found = true
		elseif dash_dash_found then
			if target_file then -- Multiple files explicit
				target_file = nil
				break
			end
			target_file = arg
		end
	end

	-- If explicit target found, go direct
	if target_file then
		start_visual_diff(target_file, args, nil, nil)
		return
	end

	-- Fetch file list for these args
	local cmd = { "git", "diff", "--name-only", unpack(args) }
	local ok, files = shell.run_command(cmd)

	if ok and #files > 0 then
		if #files == 1 then
			start_visual_diff(files[1], args, files, 1)
		else
			show_picker(files, args)
		end
		return
	end

	-- Fallback
	fallback_text(args)
end

---
-- Start a 3-way merge resolution for the current file
function M.resolve_three_way()
	require("oz.git").state.show_cache = {} -- Clear cache
	local root = git_util.get_project_root()
	if not root then
		util.Notify("Not in a git repository", "error", "oz_git")
		return
	end

	-- Auto-detect conflicted files
	local ok, conflicted_files = shell.run_command({ "git", "diff", "--name-only", "--diff-filter=U" }, root)
	if not ok or #conflicted_files == 0 then
		util.Notify("No conflicted files to resolve", "info", "oz_git")
		return
	end

	local current_file = vim.fs.normalize(vim.fn.expand("%:p"))
	local target_file = nil

	-- Check if current file is conflicted
	for _, f in ipairs(conflicted_files) do
		local abs = vim.fs.normalize(root .. "/" .. f)
		if abs == current_file then
			target_file = abs
			break
		end
	end

	-- If current file is not conflicted, pick the first one
	if not target_file then
		target_file = vim.fs.normalize(root .. "/" .. conflicted_files[1])
		vim.cmd("edit " .. vim.fn.fnameescape(target_file))
	end

	local file_path = vim.fn.expand("%:p")
	local rel_path = file_path:sub(#root + 2)

	-- Fetch versions: :1 (Base), :2 (Ours/Local), :3 (Theirs/Remote)
	local contents = {
		base = get_content(":1:" .. rel_path),
		ours = get_content(":2:" .. rel_path),
		theirs = get_content(":3:" .. rel_path),
	}

	local work_buf = vim.api.nvim_get_current_buf()
	local ft = vim.bo.filetype

	local function create_merge_buf(name, content)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
		pcall(vim.api.nvim_buf_set_name, buf, name)
		vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		return buf
	end

	local ours_buf = create_merge_buf("OURS (Local)", contents.ours)
	local base_buf = create_merge_buf("BASE (Common Ancestor)", contents.base)
	local theirs_buf = create_merge_buf("THEIRS (Remote)", contents.theirs)

	-- Create Layout
	vim.cmd("tabnew")

	-- Top-Left (Ours)
	local ours_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(ours_win, ours_buf)
	vim.api.nvim_set_option_value("number", true, { win = ours_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = ours_win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = ours_win })
	vim.cmd("diffthis")

	-- Top-Mid (Base)
	vim.cmd("rightbelow vsplit")
	local base_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(base_win, base_buf)
	vim.api.nvim_set_option_value("number", true, { win = base_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = base_win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = base_win })
	vim.cmd("diffthis")

	-- Top-Right (Theirs)
	vim.cmd("rightbelow vsplit")
	local theirs_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(theirs_win, theirs_buf)
	vim.api.nvim_set_option_value("number", true, { win = theirs_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = theirs_win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = theirs_win })
	vim.cmd("diffthis")

	-- Bottom (Work)
	vim.cmd("botright split")
	local result_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(result_win, work_buf)
	vim.api.nvim_set_option_value("number", true, { win = result_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = result_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = result_win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = result_win })
	vim.cmd("diffthis")
	vim.cmd("resize 15")

	local is_closing = false
	local function close_merge()
		if is_closing then
			return
		end
		is_closing = true
		pcall(vim.cmd, "tabclose")
	end

	local au_group = vim.api.nvim_create_augroup("OzGitMerge_" .. ours_buf, { clear = true })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = au_group,
		pattern = { tostring(ours_win), tostring(base_win), tostring(theirs_win), tostring(result_win) },
		callback = function()
			close_merge()
		end,
	})

	-- Helper Keymaps
	local function get_diff(buf_from)
		vim.api.nvim_set_current_win(result_win)

		local cur_line = vim.fn.line(".")
		local max_lines = vim.api.nvim_buf_line_count(0)

		-- Find Start (<<<<<<<)
		local start_line = nil
		for i = cur_line, 1, -1 do
			local line = vim.fn.getline(i)
			if line:match("^<<<<<<<") then
				start_line = i
				break
			elseif line:match("^>>>>>>>") and i ~= cur_line then
				break
			end
		end

		-- Find End (>>>>>>>)
		local end_line = nil
		if start_line then
			for i = cur_line, max_lines do
				local line = vim.fn.getline(i)
				if line:match("^>>>>>>>") then
					end_line = i
					break
				elseif line:match("^<<<<<<<") and i ~= start_line then
					break
				end
			end
		end

		if start_line and end_line then
			vim.cmd(start_line .. "," .. end_line .. "diffget " .. buf_from)
			vim.cmd("diffupdate")
		else
			vim.cmd("diffget " .. buf_from)
		end
	end

	local map_opts = { buffer = work_buf, noremap = true, silent = true }
	vim.keymap.set("n", "<leader>1", function()
		get_diff(ours_buf)
	end, vim.tbl_extend("force", map_opts, { desc = "Get change from OURS" }))
	vim.keymap.set("n", "<leader>2", function()
		get_diff(base_buf)
	end, vim.tbl_extend("force", map_opts, { desc = "Get change from BASE" }))
	vim.keymap.set("n", "<leader>3", function()
		get_diff(theirs_buf)
	end, vim.tbl_extend("force", map_opts, { desc = "Get change from THEIRS" }))

	-- Jumps
	vim.keymap.set("n", "<leader>j", function()
		for _, pattern in ipairs({ "^<<<<<<<", "^=====", "^>>>>>>" }) do
			if vim.fn.search(pattern, "W") ~= 0 then
				return
			end
		end
	end, { buffer = work_buf, silent = true, desc = "Next conflict marker" })

	vim.keymap.set("n", "<leader>k", function()
		for _, pattern in ipairs({ "^>>>>>>", "^=====", "^<<<<<<<" }) do
			if vim.fn.search(pattern, "Wb") ~= 0 then
				return
			end
		end
	end, { buffer = work_buf, silent = true, desc = "Prev conflict marker" })

	-- Jump File
	local function jump_file(direction)
		local r_root = git_util.get_project_root()
		local ok_j, out = shell.run_command({ "git", "diff", "--name-only", "--diff-filter=U" }, r_root)
		if not ok_j or #out == 0 then
			util.Notify("No conflicted files found.", "warn", "oz_git")
			return
		end

		local current_file_j = vim.fs.normalize(vim.fn.expand("%:p"))
		local index = nil
		for i, file in ipairs(out) do
			if vim.fs.normalize(r_root .. "/" .. file) == current_file_j then
				index = i
				break
			end
		end

		if not index then
			return
		end

		local next_index = (index + direction - 1) % #out + 1
		local target_file_j = vim.fs.normalize(r_root .. "/" .. out[next_index])

		close_merge()
		vim.cmd("edit " .. vim.fn.fnameescape(target_file_j))
		M.resolve_three_way()
	end

	vim.keymap.set("n", "]f", function()
		jump_file(1)
	end, { buffer = work_buf, desc = "Next conflicted file" })
	vim.keymap.set("n", "[f", function()
		jump_file(-1)
	end, { buffer = work_buf, desc = "Prev conflicted file" })

	-- Pick File
	vim.keymap.set("n", "<leader>e", function()
		local ok_p, c_files = shell.run_command({ "git", "diff", "--name-only", "--diff-filter=U" }, root)
		if not ok_p or #c_files == 0 then
			util.Notify("No conflicted files found.", "warn", "oz_git")
			close_merge()
			return
		end

		vim.ui.select(c_files, { prompt = "Select Conflicted File:" }, function(choice)
			if not choice then
				return
			end
			close_merge()
			vim.cmd("edit " .. vim.fn.fnameescape(vim.fs.normalize(root .. "/" .. choice)))
			M.resolve_three_way()
		end)
	end, { buffer = work_buf, desc = "Pick conflicted file" })

	-- Help
	vim.keymap.set("n", "g?", function()
		local leader = vim.g.mapleader or "\\"
		require("oz.util.help_keymaps").show_maps({
			group = {
				["Resolution Actions"] = {
					leader .. "1",
					leader .. "2",
					leader .. "3",
					leader .. "j",
					leader .. "k",
					"]f",
					"[f",
					leader .. "e",
					"gq",
				},
			},
			show_general = false,
		})
	end, { buffer = work_buf, desc = "Show 3-way merge help" })

	-- Quit
	vim.keymap.set("n", "gq", function()
		close_merge()
		vim.api.nvim_echo({ { "" } }, false, {})
	end, { buffer = work_buf, desc = "Exit 3-way merge" })
	util.inactive_echo("press 'g?' to see available mappings.")
end

return M
