local M = {}
local util = require("oz.util")

local function ft_options()
	vim.cmd([[setlocal signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable]])
	vim.bo.bufhidden = "wipe"
	vim.bo.buftype = "nofile"
	vim.bo.swapfile = false
end

local grab_flags = {}
local grab_hashs = {}
local grab_files = {}
local grab_notify = false

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
					table.insert(grab_flags, flag)
					vim.api.nvim_echo(
						{ { ":Git " .. command .. " " }, { table.concat(grab_flags, " "), "@attribute" } },
						true,
						{}
					)
				elseif #grab_flags ~= 0 then
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

local function if_grabed_enter()
	if #grab_hashs ~= 0 then
		vim.api.nvim_feedkeys(":" .. table.concat(grab_hashs, " "), "n", false)
		grab_hashs = {}
	elseif #grab_files ~= 0 then
		vim.api.nvim_feedkeys(":" .. table.concat(grab_files, " "), "n", false)
		grab_files = {}
	else
		return false
	end
	vim.schedule(function()
		vim.api.nvim_input("<Home>Git <left> ")
	end)
	return true
end

local function ft_mappings(buf)
	vim.keymap.set("n", "q", function()
		vim.cmd("close")
	end, { buffer = buf, silent = true, desc = "[oz_git]close" })

	-- GRAB key
	vim.keymap.set("n", "<C-g>", function()
		if not grab_notify then
			util.Notify("You can press 'Enter' to enter cmdline.", nil, "oz_git")
            grab_notify = true
		end
		local cfile = vim.fn.expand("<cfile>")

		if cfile:match("^[0-9a-f][0-9a-f]*$") and #cfile >= 7 and #cfile <= 40 then -- grab hashes
			table.insert(grab_hashs, cfile)
			vim.api.nvim_echo({ { ":Git | " }, { table.concat(grab_hashs, " "), "@attribute" } }, true, {})
		else
			local absolute_path = vim.fs.normalize(vim.fn.getcwd() .. "/" .. cfile)

			if vim.fn.filereadable(absolute_path) == 1 or vim.fn.isdirectory(absolute_path) == 1 then -- grab files
				table.insert(grab_files, cfile)
				vim.api.nvim_echo({ { ":Git | " }, { table.concat(grab_files, " "), "@attribute" } }, true, {})
			else
				if not extract_git_command_and_flag(true) then -- grab flags
					util.Notify("Nothing to grab.", "warn", "oz_git")
				end
			end
		end
	end, { buffer = buf, silent = true, desc = "[oz_git]cmd execute on cursor entry." })

	-- ENTER key
	vim.keymap.set("n", "<cr>", function()
		if not if_grabed_enter() then -- if any grabbed thing present then open that else do below
			local cfile = vim.fn.expand("<cfile>")

			if cfile:match("^[0-9a-f][0-9a-f]*$") and #cfile >= 7 and #cfile <= 40 then -- show hash
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
		else
			grab_notify = false
		end
	end, { buffer = buf, silent = true, desc = "[oz_git]open cursor entry." })
end

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

-- In your plugin's Lua file
function M.oz_git_hl()
	local oz_git_syntax = vim.api.nvim_create_augroup("OzGitSyntax", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "oz_git",
		group = oz_git_syntax,
		callback = function(event)
			ft_options()
			ft_hl()
			ft_mappings(event.buf)
		end,
	})
end

return M
