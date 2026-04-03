local M = {}
local util = require("oz.util")
local git = require("oz.git")
local log_util = require("oz.git.log.util")
local g_util = require("oz.util.git")

function M.switch_branch()
	local branches = g_util.get_branch()
	util.pick(branches, {
		title = "Switch branch",
		on_select = function(choice)
			if choice then
				util.setup_hls({ "OzCmdPrompt" })
				vim.api.nvim_echo({ { ":Git! switch " .. choice, "OzCmdPrompt" } }, false, {})
				vim.cmd("Git! switch " .. choice)
			end
		end,
	})
end

function M.new_branch()
	local hash = log_util.get_selected_hash()
	local b_name = util.UserInput("New Branch Name:")
	if b_name and vim.trim(b_name) ~= "" then
		local cmd = "Git branch " .. b_name
		if #hash > 0 then
			cmd = cmd .. " " .. hash[1]
		end
		log_util.run_n_refresh(cmd)
	end
end

function M.new_branch_local()
	local b_name = util.UserInput("New Branch Name:")
	if b_name and vim.trim(b_name) ~= "" then
		local cmd = string.format("Git branch %s HEAD", b_name)
		log_util.run_n_refresh(cmd)
	end
end

function M.checkout_new_branch()
	local hash = log_util.get_selected_hash()
	local b_name = util.UserInput("New Branch Name:")
	if b_name and vim.trim(b_name) ~= "" then
		local cmd = "Git switch -c " .. b_name
		if #hash > 0 then
			cmd = cmd .. " " .. hash[1]
		end
		log_util.run_n_refresh(cmd)
	end
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switch",
			items = {
				{ key = "b", cb = M.switch_branch, desc = "Switch branch" },
			},
		},
		{
			title = "Creation",
			items = {
				{ key = "n", cb = M.new_branch, desc = "Create new branch from commit under cursor" },
				{ key = "N", cb = M.new_branch_local, desc = "Create new branch from HEAD" },
				{ key = "c", cb = M.checkout_new_branch, desc = "Checkout new branch" },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						local hash = log_util.get_selected_hash()
						local cmd = "Git branch " .. flags .. " "
						if #hash > 0 then
							cmd = cmd .. " " .. hash[1]
						end
						util.set_cmdline(cmd)
					end,
					desc = "Branch (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "b", function()
		util.show_menu("Branch Actions", options)
	end, { buffer = buf, desc = "Branch Actions", nowait = true, silent = true })
end

return M
