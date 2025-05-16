local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local win = require("oz.util.win")

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
					util.tbl_monitor().start_monitoring(grab_flags, { -- keeps echoing ..
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
					util.tbl_monitor().stop_monitoring(grab_flags)
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
		util.tbl_monitor().stop_monitoring(grab_hashs)
		g_util.set_cmdline("Git | " .. table.concat(grab_hashs, " "))
		grab_hashs = {}
	elseif #grab_files ~= 0 then
		util.tbl_monitor().stop_monitoring(grab_files)
		g_util.set_cmdline("Git | " .. table.concat(grab_files, " "))
		grab_files = {}
	else
		return false
	end
	return true
end

-- mappings
local function ft_mappings(buf)
	local user_mappings = require("oz.git").user_config.mappings
	local map = util.Map

	map("n", "q", function()
		vim.cmd("close")
	end, { buffer = buf, desc = "close cmd buffer." })

	-- Pick mapping
	map("n", user_mappings.toggle_pick, function()
		local cfile = vim.fn.expand("<cfile>")

		if cfile:match("^[0-9a-f][0-9a-f]*$") and #cfile >= 7 and #cfile <= 40 then -- grab hashes
			util.tbl_insert(grab_hashs, cfile)
			vim.notify_once("press 'a/i' to enter cmdline.")
			util.tbl_monitor().start_monitoring(grab_hashs, { -- keeps echoing ..
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
				vim.notify_once("press 'a/i' to enter cmdline.")
				util.tbl_monitor().start_monitoring(grab_files, { -- keeps echoing ..
					interval = 2000,
					buf = buf,
					on_active = function(t)
						vim.api.nvim_echo({ { ":Git | " }, { table.concat(t, " "), "@attribute" } }, false, {})
					end,
				})
			else
				if not extract_git_command_and_flag(true) then -- grab flags
					util.Notify("Nothing to pick.", "warn", "oz_git")
				end
			end
		end
	end, { buffer = buf, desc = "pick any valid entry under cursor. <*>" })

	-- enter cmdline
	map("n", { "i", "a" }, function()
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
					end
				end
			end
		end
	end, { buffer = buf, desc = "open any valid entry under cursor." })

	map("n", "<cr>", function()
		if not extract_git_command_and_flag() then
			if vim.api.nvim_get_current_line():match([[https?://[^\s]+]]) then -- if on url
				vim.cmd("normal gx")
			else -- press <cr>
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
			end
		end
	end, { buffer = buf, desc = "press enter on things then you'll know what it can do. <*>" })

	-- refresh
	map("n", "<C-r>", function()
		require("oz.git").run_git_job(git_cmd.cur_cmd)
	end, { buffer = buf, desc = "refresh current cmd buffer(by rerunning prev cmd)." })

	-- discard grab
	map("n", user_mappings.unpick_all, function()
		grab_hashs, grab_files, grab_flags =
			#grab_hashs > 0 and {} or grab_hashs,
			#grab_files > 0 and {} or grab_files,
			#grab_flags > 0 and {} or grab_flags
		vim.api.nvim_echo({ { "" } }, false, {})
		util.Notify("All picked items have been removed.", nil, "oz_git")
		util.tbl_monitor().stop_all_monitoring()
	end, { buffer = buf, desc = "discard any picked entry." })

	map("n", "<C-o>", function()
		if git_cmd.prev_cmd then
			vim.cmd("Git " .. git_cmd.prev_cmd)
		end
	end, { remap = false, buffer = buf, desc = "go back to previous cmd buffer." })

	map("n", "<C-i>", function()
		if git_cmd.next_cmd then
			vim.cmd("Git " .. git_cmd.next_cmd)
		end
	end, { remap = false, buffer = buf, desc = "go to next cmd buffer." })

	-- open reflog
	map("n", "I", "<cmd>Git reflog<cr>", { buffer = buf, desc = "Open reflog" })

	-- show help
	map("n", "g?", function()
		local show_map = require("oz.util.help_keymaps")
		show_map.show_maps({
			group = {
				["Pick mappings"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" },
			},
		})
	end, { buffer = buf, desc = "show all keymaps." })
end

-- highlights
local function oz_git_win_hl()
	vim.cmd("syntax clear")

	-- Syntax matches
	vim.cmd([[
        syntax match @attribute /[0-9a-f]\{7,40\}/ containedin=ALL
        syntax match @function /^Author:/ containedin=ALL
        syntax match @function /^Date:/ containedin=ALL

        syntax match @error /^\<error:\>\|\<fatal:\>/
        syntax match DiagnosticUnderlineOk /\v(https?|ftp|file):\/\/\S+/
    ]])

	-- diff
	vim.cmd([[
        syntax match @diff.delta /^@@ .\+@@/
        syntax match @diff.plus /^+.\+$/
        syntax match @diff.minus /^-.\+$/
        syntax match @field /^diff --git .\+$/
        syntax match @field /^\(---\|+++\) .\+$/
    ]])
end

function M.open_oz_git_win(lines, cmd)
	if not lines then
		return
	end
	if cmd then
		set_cmd_history(cmd)
	end

	local win_type
	if #lines < 50 then
		local height = math.min(math.max(#lines, 7), 15)
		win_type = ("bot %s"):format(height)
	else
		win_type = "tab"
	end

	-- open win
	win.open_win("oz_git", {
		lines = lines,
		win_type = win_type,
		reuse = false,
		callback = function(buf_id, win_id)
			M.oz_git_buf = buf_id
			M.oz_git_win = win_id

			-- opts
			vim.cmd([[setlocal ft=oz_git signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
			vim.opt_local.fillchars:append({ eob = " " })

			-- async
			vim.fn.timer_start(10, function()
				oz_git_win_hl()
			end)
			vim.fn.timer_start(100, function()
				ft_mappings(M.oz_git_buf)
			end)
		end,
	})

	return M.oz_git_buf, M.oz_git_win
end

return M
