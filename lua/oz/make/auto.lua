local M = {}
local util = require("oz.util")
local cache = require("oz.caching")

local json_name = "makeprg"
local automake_id
local session_makeprg = {}

--- get makeprg
---@param project_root string
function M.get_makeprg(project_root)
	local res = session_makeprg[project_root]
	if not res then
		res = cache.get_data(project_root, json_name) or vim.o.makeprg
        session_makeprg[project_root] = res
	end
    return res
end

-- auto save makeprg
function M.makeprg_autosave()
	-- get if option changed
	vim.api.nvim_create_autocmd("OptionSet", {
		pattern = "makeprg",
		callback = function()
			local current_val = vim.o.makeprg
			local project_root = util.GetProjectRoot()
			if project_root then
				cache.set_data(project_root, current_val, json_name)
				session_makeprg[project_root] = current_val
			end
		end,
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
