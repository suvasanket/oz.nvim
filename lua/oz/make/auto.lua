local M = {}
local util = require("oz.util")
local cache = require("oz.caching")

local json_name = "makeprg"
local automake_id

local function inside_dir(dir)
	if not dir then
		return
	end
	local current_file = vim.fn.expand("%:p")
	return current_file:find(dir, 1, true) == 1 -- Check if it starts with target_dir
end

-- auto save makeprg
function M.makeprg_autosave(previous_makeprg)
	-- get if option changed
	vim.api.nvim_create_autocmd("OptionSet", {
		pattern = "makeprg",
		callback = function()
			local current_val = vim.o.makeprg
			local project_root = util.GetProjectRoot()
			if project_root then
				cache.set_data(project_root, current_val, json_name)
			end
		end,
	})

	-- dynamic set makeprg
	local function set_makeprg()
		local project_root = util.GetProjectRoot()
		if inside_dir(project_root) then
			local makeprg_cmd = cache.get_data(project_root, json_name)
			if makeprg_cmd then
				vim.o.makeprg = makeprg_cmd
			end
		else
			vim.o.makeprg = previous_makeprg
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

function M.automake_cmd(opts)
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
end

return M
