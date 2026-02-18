local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local log_util = require("oz.git.log.util")
local shell = require("oz.util.shell")
local win = require("oz.util.win")

local get_selected_hash = log.get_selected_hash
local run_n_refresh = log_util.run_n_refresh

function M.switch_commit()
	local hash = get_selected_hash()
	if #hash > 0 then
		run_n_refresh("Git checkout " .. hash[1])
	end
end

function M.show_file_in_commit()
	local hash = get_selected_hash()
	if #hash == 0 then
		return
	end
	local commit_hash = hash[1]
	local root = require("oz.git.util").get_project_root()

	local ok, files = shell.run_command({ "git", "ls-tree", "-r", "--name-only", "--full-name", commit_hash }, root)
	if not ok or #files == 0 then
		util.Notify(
			"Could not list files for commit "
				.. commit_hash
				.. "\nRoot: "
				.. root
				.. "\nError: "
				.. table.concat(files or {}, "\n"),
			"error",
			"oz_git"
		)
		return
	end

	vim.ui.select(files, { prompt = "Select file to view from " .. commit_hash .. ":" }, function(choice)
		if choice then
			local ok_show, content = shell.run_command({ "git", "show", commit_hash .. ":" .. choice }, root)
			if ok_show then
				win.create_win("oz_git_log_file", {
					content = content,
					win_type = "tab",
					buf_name = string.format("%s @ %s", choice, commit_hash:sub(1, 7)),
					callback = function(buf_id, win_id)
						local ft = vim.filetype.match({ filename = choice })
						if ft then
							vim.api.nvim_set_option_value("filetype", ft, { buf = buf_id })
						end
						vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_id })
						vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf_id })
						vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
						vim.api.nvim_set_option_value("number", true, { win = win_id })
						vim.api.nvim_set_option_value("relativenumber", false, { win = win_id })
						vim.api.nvim_set_option_value("signcolumn", "no", { win = win_id })
						vim.api.nvim_set_option_value("foldcolumn", "0", { win = win_id })

						vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf_id, desc = "Close buffer", silent = true })
					end,
				})
			else
				util.Notify(
					"Could not show file "
						.. choice
						.. "\nRoot: "
						.. root
						.. "\nError: "
						.. table.concat(content or {}, "\n"),
					"error",
					"oz_git"
				)
			end
		end
	end)
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switch/Show",
			items = {
				{ key = "s", cb = M.switch_commit, desc = "Switch (checkout) to commit under cursor" },
				{ key = "f", cb = M.show_file_in_commit, desc = "Show file from commit under cursor" },
			},
		},
	}

	vim.keymap.set("n", "s", function()
		util.show_menu("Switch/Show Actions", options)
	end, { buffer = buf, desc = "Switch/Show Actions", nowait = true, silent = true })
end

return M
