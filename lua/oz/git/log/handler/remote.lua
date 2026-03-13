local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

-- helper: get remotes
local function get_remotes()
	local ok, remotes = util.run_command({ "git", "remote" })
	if ok and #remotes ~= 0 then
		return remotes
	else
		return {}
	end
end

function M.add_update()
	local initial_input = " "
	if util.shellout_str("git remote") == "" then
		initial_input = " origin "
	end
	local input_str = util.inactive_input(":Git remote add", initial_input)

	if input_str then
		local args = util.parse_args(input_str)
		local remote_name = args[1]
		local remote_url = args[2]

		if remote_name and remote_url then
			local remotes = get_remotes()
			if vim.tbl_contains(remotes, remote_name) then
				util.pick({ { key = "Yes", value = 1 }, { key = "No", value = 2 } }, {
					title = "Remote '" .. remote_name .. "' already exists. Update URL?",
					on_select = function(ans)
						if ans == 1 then
							log_util.run_n_refresh("Git remote set-url " .. remote_name .. " " .. remote_url)
						end
					end,
				})
			else
				log_util.run_n_refresh("Git remote add " .. remote_name .. " " .. remote_url)
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

	util.pick(options, {
		title = "Select remote to remove",
		on_select = function(choice)
			if choice then
				local confirm_ans = util.prompt("Really remove remote '" .. choice .. "'?", "&Yes\n&No", 2)
				if confirm_ans == 1 then
					log_util.run_n_refresh(string.format("Git remote remove %s", choice))
				end
			end
		end,
	})
end

function M.rename()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes to rename.", "info", "oz_git")
		return
	end

	util.pick(options, {
		title = "Select remote to rename",
		on_select = function(choice)
			if choice then
				local new_name = util.UserInput("New name for '" .. choice .. "':", choice)
				if new_name and new_name ~= choice then
					log_util.run_n_refresh(string.format("Git remote rename %s %s", choice, new_name))
				end
			end
		end,
	})
end

function M.prune()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes to prune.", "info", "oz_git")
		return
	end
	util.pick(options, {
		title = "Select remote to prune",
		on_select = function(choice)
			if choice then
				log_util.run_n_refresh("Git remote prune " .. choice)
			end
		end,
	})
end

function M.set_url()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes configured.", "info", "oz_git")
		return
	end

	util.pick(options, {
		title = "Select remote to set URL",
		on_select = function(choice)
			if choice then
				local current_url = util.shellout_str("git remote get-url " .. choice)
				local new_url = util.UserInput("New URL for '" .. choice .. "':", current_url)
				if new_url and new_url ~= current_url then
					log_util.run_n_refresh(string.format("Git remote set-url %s %s", choice, new_url))
				end
			end
		end,
	})
end

function M.set_head()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes configured.", "info", "oz_git")
		return
	end

	util.pick(options, {
		title = "Select remote to set HEAD (default branch)",
		on_select = function(choice)
			if choice then
				util.pick({ "pick", "auto" }, {
					title = "Set HEAD for '" .. choice .. "':",
					on_select = function(ans)
						if ans == "auto" then
							log_util.run_n_refresh(string.format("Git remote set-head %s -a", choice))
						elseif ans == "pick" then
							local branches = util.get_branch({ rem = true })
							local remote_prefix = choice .. "/"
							local filtered = {}
							for _, b in ipairs(branches) do
								if b:find("^" .. remote_prefix) then
									table.insert(filtered, b:sub(#remote_prefix + 1))
								end
							end
							util.pick(filtered, {
								title = "Select default branch for '" .. choice .. "'",
								on_select = function(branch)
									if branch then
										log_util.run_n_refresh(
											string.format("Git remote set-head %s %s", choice, branch)
										)
									end
								end,
							})
						end
					end,
				})
			end
		end,
	})
end

function M.show()
	local options = get_remotes()
	if #options == 0 then
		util.Notify("No remotes configured.", "info", "oz_git")
		return
	end

	util.pick(options, {
		title = "Select remote to show",
		on_select = function(choice)
			if choice then
				vim.cmd("Git remote show " .. choice)
			end
		end,
	})
end

function M.update()
	local options = get_remotes()
	table.insert(options, 1, "all")

	util.pick(options, {
		title = "Select remote to update",
		on_select = function(choice)
			if choice then
				if choice == "all" then
					log_util.run_n_refresh("Git remote update")
				else
					log_util.run_n_refresh("Git remote update " .. choice)
				end
			end
		end,
	})
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-f", name = "--force", type = "switch", desc = "Force" },
			},
		},
		{
			title = "Remote",
			items = {
				{ key = "a", cb = M.add_update, desc = "Add or update remotes" },
				{ key = "u", cb = M.set_url, desc = "Set remote URL" },
				{ key = "d", cb = M.remove, desc = "Remove remote" },
				{ key = "r", cb = M.rename, desc = "Rename remote" },
				{ key = "p", cb = M.prune, desc = "Prune remote" },
				{ key = "h", cb = M.set_head, desc = "Set remote HEAD" },
				{ key = "s", cb = M.show, desc = "Show remote" },
				{ key = "f", cb = M.update, desc = "Fetch/Update remote" },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = "l",
					cb = function()
						vim.cmd("Git remote -v")
					end,
					desc = "Remote list",
				},
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git remote " .. flags .. " ")
					end,
					desc = "Remote (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "M", function()
		util.show_menu("Remote Actions", options)
	end, { buffer = buf, desc = "Remote Actions", nowait = true, silent = true })
end

return M
