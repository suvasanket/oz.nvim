local M = {}
local util = require("oz.util")
local shell = require("oz.util.shell")
local oz_git_win = require("oz.git.oz_git_win")
local git_util = require("oz.git.util")

local function fallback_text(args)
	local ok, lines = shell.run_command({ "git", "diff", unpack(args) })
	if ok then
		oz_git_win.open_oz_git_win(lines, "diff " .. table.concat(args, " "))
		vim.api.nvim_buf_set_option(0, "filetype", "diff")
	end
end

local function get_content(target)
	local ok, content = shell.run_command({ "git", "show", target })
	if ok then
		return content
	end
	return { "" }
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

function start_visual_diff(target_file, args, file_list, index)
	local root = git_util.get_project_root()
	if not root then
		return fallback_text(args)
	end

	local abs_target = target_file
	if not vim.startswith(target_file, "/") then
		abs_target = root .. "/" .. target_file
	end
	abs_target = vim.fs.normalize(abs_target)

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
			lhs_name = "HEAD"
			lhs_content = get_content("HEAD:" .. rel_path)
			rhs_name = "Index"
			rhs_content = get_content(":0:" .. rel_path)
		else
			lhs_name = "Index"
			lhs_content = get_content(":0:" .. rel_path)
			rhs_name = "Working"
			rhs_is_working = true
		end
	elseif #revisions == 1 then
		lhs_name = revisions[1]
		lhs_content = get_content(revisions[1] .. ":" .. rel_path)
		if is_cached then
			rhs_name = "Index"
			rhs_content = get_content(":0:" .. rel_path)
		else
			rhs_name = "Working"
			rhs_is_working = true
		end
	elseif #revisions >= 2 then
		lhs_name = revisions[1]
		lhs_content = get_content(revisions[1] .. ":" .. rel_path)
		rhs_name = revisions[2]
		rhs_content = get_content(revisions[2] .. ":" .. rel_path)
	end

	-- Setup View
	vim.cmd("tabnew")

	-- LHS
	local lhs_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(lhs_buf, 0, -1, false, lhs_content)
	vim.api.nvim_buf_set_name(lhs_buf, lhs_name .. ":" .. rel_path)
	vim.api.nvim_buf_set_option(lhs_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(lhs_buf, "bufhidden", "wipe")
	-- Try detect ft
	if vim.fn.filereadable(abs_target) == 1 then
		local actual_ft = vim.filetype.match({ filename = abs_target })
		if actual_ft then
			vim.api.nvim_buf_set_option(lhs_buf, "filetype", actual_ft)
		end
	end
	vim.api.nvim_win_set_buf(0, lhs_buf)
	local lhs_win = vim.api.nvim_get_current_win()
	vim.cmd("diffthis")

	-- RHS
	vim.cmd("vsplit")
	local rhs_buf
	if rhs_is_working then
		vim.cmd("edit " .. abs_target)
		rhs_buf = vim.api.nvim_get_current_buf()
	else
		rhs_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(rhs_buf, 0, -1, false, rhs_content)
		vim.api.nvim_buf_set_name(rhs_buf, rhs_name .. ":" .. rel_path)
		vim.api.nvim_buf_set_option(rhs_buf, "buftype", "nofile")
		vim.api.nvim_buf_set_option(rhs_buf, "bufhidden", "wipe")
		if vim.bo[lhs_buf].filetype ~= "" then
			vim.api.nvim_buf_set_option(rhs_buf, "filetype", vim.bo[lhs_buf].filetype)
		end
		vim.api.nvim_win_set_buf(0, rhs_buf)
	end
	local rhs_win = vim.api.nvim_get_current_win()
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

		if file_list and index then
			local function jump(dir)
				local next_idx = index + dir
				if next_idx > #file_list then
					next_idx = 1
				end
				if next_idx < 1 then
					next_idx = #file_list
				end
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
					["Diff"] = { "]f", "[f", leader .. "f", "gq" },
				},
				show_general = false,
			})
		end, vim.tbl_extend("force", map_opts, { desc = "Show diff help" }))
	end

	set_diff_keymaps(lhs_buf)
	set_diff_keymaps(rhs_buf)

	util.inactive_echo("press 'g?' to see mappings.")
end

--- Open a diff window
---@param args table
function M.diff(args)
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

	-- If implicit target (buffer), check it
	if not target_file then
		local current = vim.fn.expand("%:p")
		if current ~= "" and vim.fn.filereadable(current) == 1 then
			-- Verify current buffer is relevant to diff args?
			-- Usually if no file args, git diff applies to whole repo.
			-- So current file is just ONE of them.
			-- We should prefer the list picker if there are other files.
			-- But `Git diff` on a file buffer usually expects diffing THAT file.
			-- Let's check if the diff output actually contains this file.
			-- Or simpler: Check file list first.
		end
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

--- Start a 3-way merge resolution for the current file
function M.resolve_three_way()
	local file_path = vim.fn.expand("%:p")
	if file_path == "" then
		util.Notify("No file to resolve", "error", "oz_git")
		return
	end

	local root = git_util.get_project_root()
	local rel_path = file_path:sub(#root + 2)

	-- Fetch versions: :1 (Base), :2 (Ours/Local), :3 (Theirs/Remote)
	local versions = {
		base = { cmd = ":1:" .. rel_path, name = "BASE" },
		ours = { cmd = ":2:" .. rel_path, name = "OURS" },
		theirs = { cmd = ":3:" .. rel_path, name = "THEIRS" },
	}

	local contents = {}
	for key, ver in pairs(versions) do
		local ok, content = shell.run_command({ "git", "show", ver.cmd })
		if ok then
			contents[key] = content
		else
			contents[key] = { "" } -- Handle missing version (e.g. add/add conflict)
		end
	end

	-- Setup Layout
	-- Top: Ours | Base | Theirs
	-- Bottom: Working File (Current Buffer)

	local work_buf = vim.api.nvim_get_current_buf()
	local ft = vim.bo.filetype

	-- Create Buffers
	local ours_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(ours_buf, 0, -1, false, contents.ours)
	vim.api.nvim_buf_set_name(ours_buf, "OURS (Local)")
	vim.api.nvim_buf_set_option(ours_buf, "filetype", ft)
	vim.api.nvim_buf_set_option(ours_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(ours_buf, "bufhidden", "wipe")

	local base_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, contents.base)
	vim.api.nvim_buf_set_name(base_buf, "BASE (Common Ancestor)")
	vim.api.nvim_buf_set_option(base_buf, "filetype", ft)
	vim.api.nvim_buf_set_option(base_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(base_buf, "bufhidden", "wipe")

	local theirs_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(theirs_buf, 0, -1, false, contents.theirs)
	vim.api.nvim_buf_set_name(theirs_buf, "THEIRS (Remote)")
	vim.api.nvim_buf_set_option(theirs_buf, "filetype", ft)
	vim.api.nvim_buf_set_option(theirs_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(theirs_buf, "bufhidden", "wipe")

	-- Create Layout
	vim.cmd("tabnew")

	-- Top-Left (Ours)
	local ours_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(ours_win, ours_buf)
	vim.cmd("diffthis")

	-- Top-Mid (Base)
	vim.cmd("rightbelow vsplit")
	local base_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(base_win, base_buf)
	vim.cmd("diffthis")

	-- Top-Right (Theirs)
	vim.cmd("rightbelow vsplit")
	local theirs_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(theirs_win, theirs_buf)
	vim.cmd("diffthis")

	-- Bottom (Work)
	vim.cmd("botright split")
	local result_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(result_win, work_buf)
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
		-- "diffget" from specific buffer is tricky with buffer numbers in `diffget`.
		-- `diffget //2` gets from target (ours), `//3` (theirs).
		-- Buffer numbers can also be used.
		vim.cmd("diffget " .. buf_from)
	end

	local map_opts = { buffer = work_buf, noremap = true, silent = true, desc = "Get change from OURS" }
	vim.keymap.set("n", "<localleader>2", function()
		get_diff(ours_buf)
	end, map_opts)

	map_opts.desc = "Get change from BASE"
	vim.keymap.set("n", "<localleader>1", function()
		get_diff(base_buf)
	end, map_opts)

	map_opts.desc = "Get change from THEIRS"
	vim.keymap.set("n", "<localleader>3", function()
		get_diff(theirs_buf)
	end, map_opts)

	-- Jumps
	vim.keymap.set("n", "]x", function()
		local patterns = { "^<<<<<<<", "^=====", "^>>>>>>" }
		for _, pattern in ipairs(patterns) do
			if vim.fn.search(pattern, "W") ~= 0 then
				return
			end
		end
	end, { buffer = work_buf, silent = true, desc = "Next conflict marker" })

	vim.keymap.set("n", "[x", function()
		local patterns = { "^>>>>>>", "^=====", "^<<<<<<<" }
		for _, pattern in ipairs(patterns) do
			if vim.fn.search(pattern, "Wb") ~= 0 then
				return
			end
		end
	end, { buffer = work_buf, silent = true, desc = "Prev conflict marker" })

	-- Jump File
	local function jump_file(direction)
		local r_root = git_util.get_project_root()
		local ok, out = shell.run_command({ "git", "diff", "--name-only", "--diff-filter=U" }, r_root)
		if not ok or #out == 0 then
			util.Notify("No conflicted files found.", "warn", "oz_git")
			return
		end

		local current_file = vim.fn.expand("%:p")
		-- normalize paths for comparison
		current_file = vim.fs.normalize(current_file)

		local index = nil
		for i, file in ipairs(out) do
			local abs_path = vim.fs.normalize(root .. "/" .. file)
			if abs_path == current_file then
				index = i
				break
			end
		end

		if not index then
			return
		end

		local next_index = index + direction
		if next_index > #out then
			next_index = 1
		end
		if next_index < 1 then
			next_index = #out
		end

		local target_file = vim.fs.normalize(root .. "/" .. out[next_index])

		vim.cmd("tabclose")
		vim.cmd("edit " .. target_file)
		M.resolve_three_way()
	end

	vim.keymap.set("n", "]f", function()
		jump_file(1)
	end, { buffer = work_buf, desc = "Next conflicted file" })
	vim.keymap.set("n", "[f", function()
		jump_file(-1)
	end, { buffer = work_buf, desc = "Prev conflicted file" })

	-- Help
	vim.keymap.set("n", "g?", function()
		local ll = vim.g.maplocalleader or "\\"
		require("oz.util.help_keymaps").show_maps({
			group = {
				["Resolution Actions"] = { ll .. "1", ll .. "2", ll .. "3", "]x", "[x", "]f", "[f", "gq" },
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
