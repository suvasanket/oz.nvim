local M = {}
local util = require("oz.util")
local arg_parser = require("oz.util.parse_args")
local qf = require("oz.qf")
local cache = require("oz.caching")
local win = require("oz.util.win")
local progress = require("oz.util.progress")

local json_name = "makeprg"

M.previous_makeprg = vim.o.makeprg
local automake_id

local function get_build_command(project_root)
	if not project_root or project_root == "" then
		return nil
	end

	if vim.fn.isdirectory(project_root) ~= 1 then
		return nil
	end

	local is_windows = vim.fn.has("win32") == 1

	-- Define build systems to check, in order of preference.
	local build_systems = {
		{ file = "Makefile", command = "make", platform = "any" },
		{ file = "makefile", command = "make", platform = "any" }, -- Case variation
		{ file = "build.ninja", command = "ninja", platform = "any" },

		{ file = "build.sh", command = "./build.sh", platform = "unix" },
		{ file = "build.bat", command = "build.bat", platform = "windows" },
		{ file = "build.cmd", command = "build.cmd", platform = "windows" },

		{ file = "pom.xml", command = "mvn package", platform = "any" }, -- Java Maven
		{ file = "build.gradle", command = "gradle build", platform = "any" }, -- Java/Kotlin Gradle (Groovy)
		{ file = "build.gradle.kts", command = "gradle build", platform = "any" }, -- Java/Kotlin Gradle (Kotlin DSL)
		{ file = "Cargo.toml", command = "cargo build", platform = "any" }, -- Rust Cargo

		{ file = "package.json", command = "npm run build", platform = "any" }, -- Node.js (common convention, assumes 'build' script exists)
		{ file = "CMakeLists.txt", command = "cmake --build ./build", platform = "any" }, -- Assumes out-of-source in './build' dir. Could also be 'make' or 'ninja' in the build dir.
	}

	-- Iterate and check for files
	for _, config in ipairs(build_systems) do
		local file_path = vim.fs.joinpath(project_root, config.file)

		if vim.fn.filereadable(file_path) == 1 then
			local platform_match = false
			if config.platform == "any" then
				platform_match = true
			elseif config.platform == "unix" and not is_windows then
				platform_match = true
			elseif config.platform == "windows" and is_windows then
				platform_match = true
			end

			if platform_match then
				-- Add specific notes for potentially ambiguous commands
				if config.file == "CMakeLists.txt" then
					util.Notify(
						"Note: CMake command assumes './build' directory exists and was configured.",
						"info",
						"oz_make"
					)
				elseif config.file == "package.json" then
					util.Notify("Note: 'npm run build' is a convention; check package.json scripts.", "info", "oz_make")
				end
				return config.command
			end
		end
	end

	return nil
end

-- make err win buffer mappings
local function make_err_buf_mappings(buf_id)
	util.Map("n", "q", "<cmd>close<cr>", { buffer = buf_id, desc = "close" })
	util.Map("n", "<cr>", function()
		-- jump to file
		local ok = pcall(vim.cmd, "normal! gF")

		if ok then
			local entry_buf = vim.api.nvim_get_current_buf()
			local pos = vim.api.nvim_win_get_cursor(0)

			vim.api.nvim_set_current_buf(buf_id)
			if entry_buf == buf_id then
				return
			end
			vim.cmd.wincmd("k")
			vim.api.nvim_set_current_buf(entry_buf)

			pcall(vim.api.nvim_win_set_cursor, 0, pos)
		else
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<cr>", true, false, true), "n", false)
		end
	end, { buffer = buf_id, desc = "open the entry." })
end

-- show err in a wind
local function make_err_win(lines)
	win.open_win("make_err", {
		lines = lines,
		win_type = "bot 7",
		callback = function(buf_id)
			-- opts
			vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.opt_local.fillchars:append({ eob = " " })
			local shell_name = vim.fn.fnamemodify(vim.fn.environ()["SHELL"] or vim.fn.environ()["COMSPEC"], ":t:r")
			if shell_name == "bash" or shell_name == "zsh" then
				vim.bo.ft = "sh"
			elseif shell_name == "powershell" then
				vim.bo.ft = "ps1"
			else
				vim.bo.ft = shell_name
			end

			-- mappings
			vim.fn.timer_start(100, function()
				make_err_buf_mappings(buf_id)
			end)
		end,
	})
end

local function inside_dir(dir)
	if not dir then
		return
	end
	local current_file = vim.fn.expand("%:p")
	return current_file:find(dir, 1, true) == 1 -- Check if it starts with target_dir
end

function M.Make_func(arg_str, dir)
	local cmd_tbl = arg_parser.parse_args(arg_str)
	-- local make_cmd = m_util.detect_makeprg(vim.fn.expand("%"))
	local make_cmd = vim.o.makeprg
	if make_cmd == "make" then
		local detected_cmd = get_build_command(util.GetProjectRoot())
		if detected_cmd and make_cmd ~= detected_cmd then
			-- vim.o.makeprg = detected_cmd
			make_cmd = detected_cmd
		end
	end

	table.insert(cmd_tbl, 1, make_cmd)

	local output = {}

	-- progress stuff
	local pro_title = table.concat(cmd_tbl, "")
	local u_id = util.generate_unique_id()
	progress.start_progress(u_id, { title = pro_title, fidget_lsp = "oz_make" })

	-- Start the job
	local ok, job_id = pcall(vim.fn.jobstart, cmd_tbl, {
		cwd = dir,
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output, line)
				end
			end
		end,
		on_stderr = function(_, data, _)
			-- Collect stderr lines
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output, line)
				end
			end
		end,
		on_exit = function(_, exit_code, _)
			-- progress stuff
			progress.stop_progress(u_id, {
				exit_code = exit_code,
				title = pro_title,
				message = { "Build completed successfully", "Error occured while building" },
			})

			qf.capture_lines_to_qf(output, vim.bo.ft, true)

			if #vim.fn.getqflist() == 1 then
				vim.cmd("cfirst")
			elseif #vim.fn.getqflist() > 0 then
				vim.cmd("cw | cfirst")
				util.echoprint("Issue found: resolve then continue", "healthWarning")
			else
				vim.cmd("cw")
				if exit_code ~= 0 then
					util.Notify("Consult :help efm, then set error format.", "warn", "oz_make")
					if #output > 0 then
						make_err_win(output)
					end
				end
			end
		end,
	})

	if not ok or job_id <= 0 then
		util.Notify("Cannot execute make cmd", "error", "oz_make")
		return
	end
end

-- auto save makeprg
function M.makeprg_autosave()
	-- get if option changed
	vim.api.nvim_create_autocmd("OptionSet", {
		pattern = "makeprg",
		callback = function()
			M.previous_makeprg = vim.o.makeprg
			local project_root = util.GetProjectRoot()
			if project_root then
				cache.set_data(project_root, M.previous_makeprg, json_name)
			end
		end,
	})

	-- dynamic set makeprg
	local function set_makeprg()
		local project_root = util.GetProjectRoot()
		if inside_dir(project_root) then
			M.previous_makeprg = vim.o.makeprg
			local makeprg_cmd = cache.get_data(project_root, json_name)
			if makeprg_cmd then
				vim.o.makeprg = makeprg_cmd
			end
		else
			vim.o.makeprg = M.previous_makeprg
		end
	end
	vim.api.nvim_create_autocmd("DirChanged", {
		callback = function()
			set_makeprg()
		end,
	})
	vim.api.nvim_create_autocmd("CmdLineEnter", {
		callback = function()
			set_makeprg()
		end,
		once = true,
	})
end

function M.oz_make_init(config)
	-- Make cmd
	vim.api.nvim_create_user_command("Make", function(arg)
		-- run make in cwd
		if arg.bang then
			M.Make_func(arg.args, vim.fn.getcwd())
		else
			M.Make_func(arg.args, util.GetProjectRoot()) -- run make in project root
		end
	end, { nargs = "*", desc = "[oz_make]make", bang = true })

	-- Automake cmd
	vim.api.nvim_create_user_command("AutoMake", function(opts)
		local args = opts.fargs
		local pattern, make_cmd = nil, "Make"

		if args[1] == "file" then
			pattern = vim.fn.expand("%:p")
		elseif args[1] == "filetype" then
			pattern = string.format("*.%s", vim.bo.filetype)
		elseif args[1] == "addarg" then
			make_cmd = "Make " .. (util.UserInput("Args:") or "")
		elseif args[1] == "disable" and automake_id then
			util.inactive_echo("AutoMake Stopped")
			vim.api.nvim_del_autocmd(automake_id)
			automake_id = nil
		end

		if pattern then
			if automake_id then
				vim.api.nvim_del_autocmd(automake_id)
				automake_id = nil
			else
				util.inactive_echo("Started watching: " .. pattern)
				automake_id = vim.api.nvim_create_autocmd("BufWritePost", {
					pattern = pattern,
					callback = function()
						vim.cmd(make_cmd)
					end,
				})
			end
		end
	end, {
		desc = "[oz_make]automake",
		nargs = "?",
		complete = function()
			return { "filetype", "file", "addarg", "disable" }
		end,
	})

	-- override make
	if config.override_make then
		vim.cmd([[
            cnoreabbrev <expr> make getcmdtype() == ':' && getcmdline() ==# 'make' ? 'Make' : 'make'
        ]])
	end

	-- auto save makeprg
	if config.autosave_makeprg then
		M.makeprg_autosave()
	end
end

return M
