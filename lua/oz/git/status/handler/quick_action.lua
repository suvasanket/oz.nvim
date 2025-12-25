local M = {}
local util = require("oz.util")
local status = require("oz.git.status")
local s_util = require("oz.git.status.util")
local git = require("oz.git")

local refresh = status.refresh_buf

function M.quit()
	vim.api.nvim_echo({ { "" } }, false, {})
	vim.cmd("close")
end

function M.tab()
	if s_util.toggle_section() then
		return
	end
end

function M.rename()
	local branch = s_util.get_branch_under_cursor()
	local file = s_util.get_file_under_cursor(true)[1]

	if file or branch then
		git.after_exec_complete(function(code)
			if code == 0 then
				refresh()
			end
		end, true)
	end

	if file then
		local new_name = util.UserInput("New name: ", file)
		if new_name then
			s_util.run_n_refresh("Git mv " .. file .. " " .. new_name)
		end
	elseif branch then
		local new_name = util.UserInput("New name: ", branch)
		if new_name then
			s_util.run_n_refresh("Git branch -m " .. branch .. " " .. new_name)
		end
	end
end

function M.enter_key()
	local file = s_util.get_file_under_cursor()
	local branch = s_util.get_branch_under_cursor()
	local stash = s_util.get_stash_under_cursor()

	local section = s_util.get_section_under_cursor()
	local current_branch = status.state.current_branch

	if section == "branch" then -- section branch
		if current_branch and (current_branch == "HEAD" or current_branch:match("HEAD detached")) then
			util.set_cmdline("Git checkout ")
		else
			vim.cmd("Git show-branch -a")
		end
	elseif section == "stash" then -- section stash
		vim.cmd("Git stash list --stat")
	elseif branch then -- branch
		s_util.run_n_refresh(string.format("Git switch %s --quiet", branch))
	elseif stash.index then -- stash
		s_util.run_n_refresh(string.format("Git stash show stash@{%d}", stash.index))
	elseif #file > 0 and (vim.fn.filereadable(file[1]) == 1 or vim.fn.isdirectory(file[1]) == 1) then -- file.
		vim.cmd("wincmd k | edit " .. file[1])
	end
end

return M
