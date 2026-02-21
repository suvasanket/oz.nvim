local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local git = require("oz.git")
local s_util = require("oz.git.status.util")

local refresh = status.refresh_buf
local state = status.state

-- helper: get remotes
local function get_remotes()
	local ok, remotes = util.run_command({ "git", "remote" }, state.cwd)
	if ok and #remotes ~= 0 then
		state.remotes = remotes
		return remotes
	else
		return {}
	end
end

function M.add_update()
	local initial_input = " "
	if util.shellout_str("git remote") == "" then
		initial_input = " origin " -- Suggest 'origin' if no remotes exist
	end
	local input_str = util.inactive_input(":Git remote add", initial_input)

	if input_str then
		local args = util.parse_args(input_str)
		local remote_name = args[1]
		local remote_url = args[2]

		if remote_name and remote_url then
			local remotes = get_remotes()
			if vim.tbl_contains(remotes, remote_name) then
				-- Remote exists, ask to update URL
				local ans = util.prompt(
					"Remote '" .. remote_name .. "' already exists. Update URL?",
					"&Yes\n&No",
					2 -- Default to No
				)
				if ans == 1 then
					git.on_job_exit("remote_set_url", {
						callback = function(ev)
							if ev.exit_code == 0 then
								util.Notify("Updated URL for remote '" .. remote_name .. "'.", nil, "oz_git")
								refresh() -- Refresh status potentially
							end
						end,
						once = true,
					})
					vim.cmd("G remote set-url " .. remote_name .. " " .. remote_url)
				end
			else
				-- Add new remote
				git.on_job_exit("remote_add", {
					callback = function(ev)
						if ev.exit_code == 0 then
							util.Notify("Added new remote '" .. remote_name .. "'.", nil, "oz_git")
							refresh() -- Refresh status potentially
						end
					end,
					once = true,
				})
				vim.cmd("G remote add " .. remote_name .. " " .. remote_url)
			end
		else
			util.Notify("Requires remote name and URL.", "warn", "oz_git")
		end
	end
end

function M.remove()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes configured.", "info", "oz_git")
		return
	end

	vim.ui.select(options, { prompt = "Select remote to remove:" }, function(choice)
		if choice then
			-- Confirmation prompt
			local confirm_ans = util.prompt("Really remove remote '" .. choice .. "'?", "&Yes\n&No", 2)
			if confirm_ans == 1 then
				s_util.run_n_refresh(string.format("Git remote remove %s", choice))
			end
		end
	end)
end

function M.rename()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes to rename.", "info", "oz_git")
		return
	end

	vim.ui.select(options, { prompt = "Select remote to rename:" }, function(choice)
		if choice then
			local new_name = util.UserInput("New name for '" .. choice .. "':", choice)
			if new_name and new_name ~= choice then
				s_util.run_n_refresh(string.format("Git remote rename %s %s", choice, new_name))
			end
		end
	end)
end

function M.prune()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes to prune.", "info", "oz_git")
		return
	end
	vim.ui.select(options, { prompt = "Select remote to prune:" }, function(choice)
		if choice then
			s_util.run_n_refresh("Git remote prune " .. choice)
		end
	end)
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Actions",
			items = {
				{ key = "a", cb = M.add_update, desc = "Add or update remotes" },
				{ key = "d", cb = M.remove, desc = "Remove remote" },
				{ key = "r", cb = M.rename, desc = "Rename remote" },
				{ key = "p", cb = M.prune, desc = "Prune remote" },
			},
		},
		{
			title = "View",
			items = {
				{
					key = "l", -- M is the menu key, l for list inside
					cb = function()
						vim.cmd("Git remote -v")
					end,
					desc = "Remote list",
				},
			},
		},
	}

	vim.keymap.set("n", "M", function()
		util.show_menu("Remote Actions", options)
	end, { buffer = buf, desc = "Remote Actions", nowait = true, silent = true })
end

return M
