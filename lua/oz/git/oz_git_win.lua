local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")

M.oz_git_buf = nil
M.oz_git_win = nil
local git_cmd = {}

local function set_cmd_history(cmd)
	if git_cmd.prev_cmd == cmd then
		git_cmd.next_cmd = git_cmd.cur_cmd
	end
	if git_cmd.cur_cmd then
		git_cmd.prev_cmd = git_cmd.cur_cmd
	end
	git_cmd.cur_cmd = cmd
end

local function ft_options()
	vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
	vim.bo.bufhidden = "wipe"
	vim.bo.swapfile = false
end

local grab_flags = {}
local grab_hashs = {}
local grab_files = {}

local function extract_git_command_and_flag(if_grab)
	local current_line = vim.api.nvim_get_current_line()

	local flag = current_line:match("%-%-[%w%[%]%-]+")
	if not flag then
		flag = current_line:match("%-[%w]")
	end

	if flag then
		flag = flag:gsub("%[", ""):gsub("%]", "")

		local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""

		if first_line:match("usage: git") then
			local command = first_line:match("usage: git ([%w%-]+)")

			if command then
				local final_command = command .. " " .. flag
				if if_grab then
					util.tbl_insert(grab_flags, flag)
					vim.notify_once("press 'Enter' to enter cmdline, <C-c> to reset.")
					g_util.start_monitoring(grab_flags, { -- keeps echoing ..
						interval = 2000,
						buf = M.oz_git_buf,
						on_active = function(t)
							vim.api.nvim_echo(
								{ { ":Git " .. command .. " " }, { table.concat(t, " "), "@attribute" } },
								false,
								{}
							)
						end,
					})
				elseif #grab_flags ~= 0 then
					g_util.stop_monitoring(grab_flags)
					vim.api.nvim_feedkeys(":Git " .. command .. " " .. table.concat(grab_flags, " "), "n", false)
					grab_flags = {}
				else
					vim.api.nvim_feedkeys(":Git " .. final_command, "n", false)
				end
				return true
			end
		end
	end
	return false
end

-- helper: if grabbed
local function if_grabed_enter()
	if #grab_hashs ~= 0 then
		g_util.stop_monitoring(grab_hashs)
		g_util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
		grab_hashs = {}
	elseif #grab_files ~= 0 then
		g_util.stop_monitoring(grab_files)
		g_util.set_cmdline("Git | " .. table.concat(grab_files, " "))
		grab_files = {}
	else
		return false
	end
	return true
end

-- mappings
local function ft_mappings(buf)
	vim.keymap.set("n", "q", function()
		vim.cmd("close")
	end, { buffer = buf, silent = true, desc = "close cmd buffer." })

	-- FIXME: potential ref C-g and CR
	-- GRAB key
	vim.keymap.set("n", "<C-g>", function()
		local cfile = vim.fn.expand("<cfile>")

		if cfile:match("^[0-9a-f][0-9a-f]*$") and #cfile >= 7 and #cfile <= 40 then -- grab hashes
			util.tbl_insert(grab_hashs, cfile)
			vim.notify_once("press 'Enter' to enter cmdline, <C-c> to reset.")
			g_util.start_monitoring(grab_hashs, { -- keeps echoing ..
				interval = 2000,
				buf = buf,
				on_active = function(t)
					vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
				end,
			})
		else
			local absolute_path = vim.fs.normalize(vim.fn.getcwd() .. "/" .. cfile)

			if vim.fn.filereadable(absolute_path) == 1 or vim.fn.isdirectory(absolute_path) == 1 then -- grab files
				util.tbl_insert(grab_files, cfile)
				vim.notify_once("press 'Enter' to enter cmdline, <C-c> to reset.")
				g_util.start_monitoring(grab_files, { -- keeps echoing ..
					interval = 2000,
					buf = buf,
					on_active = function(t)
						vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
					end,
				})
			else
				if not extract_git_command_and_flag(true) then -- grab flags
					util.Notify("Nothing to grab.", "warn", "oz_git")
				end
			end
		end
	end, { buffer = buf, silent = true, desc = "pick any valid entry under cursor." })

	-- ENTER key
	vim.keymap.set("n", "<cr>", function()
		if not if_grabed_enter() then -- if any grabbed thing present then open that else do below
			local cfile = vim.fn.expand("<cfile>")

			if cfile:match("^[0-9a-f][0-9a-f]*$") and #cfile >= 7 and #cfile <= 40 then -- show hash
				if vim.bo.buftype == "terminal" then
					vim.cmd("close")
				end
				vim.cmd("Git show " .. cfile)
			else
				local cwd = vim.fn.getcwd()
				local absolute_path = vim.fs.normalize(cwd .. "/" .. cfile)
				if vim.fn.filereadable(absolute_path) == 1 or vim.fn.isdirectory(absolute_path) == 1 then -- edit file
					vim.cmd.wincmd("p")
					vim.cmd("edit " .. absolute_path)
				else
					local line = vim.api.nvim_get_current_line()
					if line:match("^%s*git%s+") then
						line = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^git%s+", "")
						vim.api.nvim_feedkeys(":Git " .. line, "n", false)
					elseif not extract_git_command_and_flag() then -- edit flags
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
					end
				end
			end
		end
	end, { buffer = buf, silent = true, desc = "open any valid entry under cursor." })

	-- refresh
	vim.keymap.set("n", "<C-r>", function()
		require("oz.git").run_git_cmd(git_cmd.cur_cmd)
	end, { buffer = buf, silent = true, desc = "refresh current cmd buffer(by rerunning prev cmd)." })

	-- discard grab
	vim.keymap.set("n", "<C-c>", function()
		grab_hashs, grab_files, grab_flags =
			#grab_hashs > 0 and {} or grab_hashs,
			#grab_files > 0 and {} or grab_files,
			#grab_flags > 0 and {} or grab_flags
		vim.api.nvim_echo({ { "" } }, false, {})
		util.Notify("All picked items have been removed.", nil, "oz_git")
		g_util.stop_all_monitoring()
	end, { buffer = buf, silent = true, desc = "discard any picked entry." })

	-- show help
	vim.keymap.set("n", "g?", function()
		util.Show_buf_keymaps()
	end, { buffer = buf, silent = true, desc = "show all keymaps." })

	vim.keymap.set("n", "<C-o>", function()
		if git_cmd.prev_cmd then
			vim.cmd("Git " .. git_cmd.prev_cmd)
		end
	end, { remap = false, buffer = buf, silent = true, desc = "go back to previous cmd buffer." })

	vim.keymap.set("n", "<C-i>", function()
		if git_cmd.next_cmd then
			vim.cmd("Git " .. git_cmd.next_cmd)
		end
	end, { remap = false, buffer = buf, silent = true, desc = "go to next cmd buffer." })
end

-- highlights
local function ft_hl()
	vim.cmd("syntax clear")

	-- Syntax matches
	vim.cmd("syntax match ozGitAuthor '\\<Author\\>' containedin=ALL")
	vim.cmd("syntax match ozGitDate '\\<Date\\>' containedin=ALL")
	vim.cmd("syntax match ozGitCommitHash '\\<[0-9a-f]\\{7,40}\\>' containedin=ALL")
	vim.cmd([[syntax match ozGitBranchName /\(On branch \)\@<=\S\+/ contained]])
	vim.cmd([[syntax match ozGitSection /^Untracked files:$/]])
	vim.cmd([[syntax match ozGitSection /^Changes not staged for commit:$/]])
	vim.cmd([[syntax match ozGitModified /^\s\+modified:\s\+.*$/]])
	vim.cmd([[syntax match ozGitUntracked /^\s\+\%(\%(modified:\)\@!.\)*$/]])

	vim.cmd([[syntax match ozGitDiffMeta /^@@ .\+@@/]])
	vim.cmd([[syntax match ozGitDiffAdded /^+.\+$/]])
	vim.cmd([[syntax match ozGitDiffRemoved /^-.\+$/]])
	vim.cmd([[syntax match ozGitDiffHeader /^diff --git .\+$/]])
	vim.cmd([[syntax match ozGitDiffFile /^\(---\|+++\) .\+$/]])

	-- Highlight groups
	vim.cmd("highlight default link ozGitBranchName @function")
	vim.api.nvim_set_hl(0, "ozGitUntracked", { fg = "#757575" })
	vim.cmd("highlight default link ozGitModified @diff.delta")
	vim.cmd("highlight default link ozGitSection @function")

	vim.cmd("highlight default link ozGitDiffAdded @diff.plus")
	vim.cmd("highlight default link ozGitDiffRemoved @diff.minus")
	vim.cmd("highlight default link ozGitDiffMeta @diff.delta")
	vim.cmd("highlight default link ozGitDiffFile @function")
	vim.cmd("highlight default link ozGitDiffHeader @comment.todo")

	vim.cmd("highlight default link ozGitAuthor @function")
	vim.cmd("highlight default link ozGitDate @function")
	vim.cmd("highlight default link ozGitCommitHash @attribute")
end

-- oz git ft
function M.oz_git_ft()
	local oz_git_ft_gp = vim.api.nvim_create_augroup("OzGitFt", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "oz_git",
		group = oz_git_ft_gp,
		once = true,
		callback = function(event)
			ft_options()
			ft_hl()
			ft_mappings(event.buf)
		end,
	})
	return true
end

function M.open_oz_git_win(lines, cmd, type)
	set_cmd_history(cmd)
	local height = math.min(math.max(#lines, 7), 15)

	if M.oz_git_buf == nil or not vim.api.nvim_win_is_valid(M.oz_git_win) then
		M.oz_git_buf = vim.api.nvim_create_buf(false, true)

		vim.cmd("botright " .. height .. "split")
		vim.cmd("resize " .. height)

		M.oz_git_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(M.oz_git_win, M.oz_git_buf)

		vim.api.nvim_buf_set_lines(M.oz_git_buf, 0, -1, false, lines)

		vim.api.nvim_buf_set_name(M.oz_git_buf, string.format("oz_git://%s", type))
		if M.oz_git_ft() then
			vim.api.nvim_buf_set_option(M.oz_git_buf, "ft", "oz_git")
		else
			vim.api.nvim_buf_set_option(M.oz_git_buf, "ft", "git")
		end

		vim.api.nvim_create_autocmd("BufDelete", {
			buffer = M.oz_git_buf,
			callback = function()
				M.oz_git_buf = nil
				M.oz_git_win = nil
				git_cmd = {} -- FIXME will not clear the tbl.
			end,
		})
	else
		vim.api.nvim_set_current_win(M.oz_git_win)
		vim.cmd("resize " .. height)
		vim.api.nvim_buf_set_option(M.oz_git_buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.oz_git_buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.oz_git_buf, "modifiable", false)
	end

	return M.oz_git_buf, M.oz_git_win
end

return M
