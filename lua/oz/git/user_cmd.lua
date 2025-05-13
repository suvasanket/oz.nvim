local M = {}
local util = require("oz.util")
local shell = require("oz.util.shell")
local g_util = require("oz.git.util")

local function find_substring(str, substrings)
	for _, substring in pairs(substrings) do
		if str:find(substring) then
			return substring
		end
	end
	return nil
end

--- user_cmd init
function M.init()
	local main = require("oz.git")

	-- :Git
	g_util.User_cmd({ "Git", "G" }, function(opts)
		if g_util.if_in_git() then
			if opts.args and #opts.args > 0 then
				main.run_git_job(opts.args)
			else
				require("oz.git.status").GitStatus()
				vim.api.nvim_set_hl(0, "ozHelpEcho", { fg = "#606060" })
				vim.api.nvim_echo({ { "press g? to see all available keymaps.", "ozHelpEcho" } }, false, {})
			end
		elseif opts.args and opts.args:find("init") then
			main.run_git_job(opts.args)
		else
			util.Notify("You are not in a git repo. Try :Git init", "warn", "oz_git")
		end
	end, {
		nargs = "*",
		desc = "oz_git",
		complete = function(arglead, cmdline, cursorpos)
			return require("oz.git.complete").complete(arglead, cmdline, cursorpos)
		end,
	})

	-- log
	vim.api.nvim_create_user_command("GitLog", function(opts)
		if g_util.if_in_git() then
			if opts.args ~= "" then
				local args_table = vim.split(opts.args, "%s+")
				require("oz.git.git_log").commit_log({ level = 1 }, args_table)
			else
				require("oz.git.git_log").commit_log()
			end
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", desc = "oz_git log" })

	-- Gr
	g_util.User_cmd({ "Gr", "Gread" }, function(opts)
		if g_util.if_in_git() then
			local file = opts.args
			if file == "" then
				local files = shell.shellout_tbl("git diff --name-only HEAD")
				file = find_substring(vim.fn.expand("%:p"), files)
			else
				vim.cmd("edit " .. file)
			end

			local read_content = vim.fn.systemlist({ "git", "show", ":" .. file })
			if #read_content > 0 then
				vim.api.nvim_buf_set_lines(0, 0, -1, false, read_content)
			end
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "?", complete = "file", desc = "oz_git: undo unstaged changes." })

	-- Gw
	g_util.User_cmd({ "Gw", "Gwrite" }, function(opts)
		local file_name = vim.trim(opts.args)
		if g_util.if_in_git() then
			if file_name == "" then
				local ok = pcall(vim.cmd, "w")
				if ok then
					vim.cmd("Git add %")
				end
			else
				local old_name = vim.fn.expand("%")
				local ok = pcall(vim.cmd, "w", file_name)
				if ok then
					main.after_exec_complete(function()
						vim.cmd("checktime")
					end)
					vim.cmd("Git mv " .. old_name .. " " .. file_name)
				end
			end
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "*", complete = "file", desc = "oz_git: add/stage/rename current file." })

	-- :GBrowse
	g_util.User_cmd({ "GBrowse" }, function(opts)
		local path = vim.trim(opts.args)
		local oil_path = require("oil").get_current_dir()

		if g_util.if_in_git(oil_path) then
			if vim.bo.ft == "oil" then -- if in oil buffer
				path = oil_path
			elseif path == "" then -- if no arg is provided
				path = vim.fn.expand("%")
			end
			if path ~= "" then
				require("oz.git.browse").browse(path)
			end
		else
			util.Notify("You are not in a git repo.", "warn", "oz_git")
		end
	end, { nargs = "?", complete = "file", desc = "oz_git: browse file in the remote repo." })
end

return M
