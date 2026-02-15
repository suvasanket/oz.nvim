local M = {}

local default_efms = {
	python = '%E  File "%f"\\, line %l,%C%m,%Z%m',
	c = "%f:%l:%c: %m,%f:%l: %m",
	cpp = "%f:%l:%c: %m,%f:%l: %m",
	go = "%f:%l:%c: %m",
	java = "%A%f:%l: %m,%-Z%p^,%-C%.%#",
	typescript = "%f(%l\\,%c): %m,%f(%l\\,%c): %t%*[^:]: %m",
	javascript = "%f(%l\\,%c): %m",
	ruby = "%E%f:%l: %m",
	php = "%EParse error: %m in %f on line %l",
}

--- capture lines to quickfix
---@param lines table
---@param jobid integer
function M.capture_lines_to_qf(lines, jobid)
	local efm = nil
	local job = require("oz.make.job").jobs[jobid]

	if vim.b.current_compiler then
		efm = vim.bo.errorformat
	else
		local project_root = job.cwd or require("oz.util").GetProjectRoot()
		local cache = require("oz.caching")
		local project_efm = project_root and cache.get_data(project_root, "oz_make_efm_project")
		local ft_efm = job.ft and cache.get_data(job.ft, "oz_make_efm_ft")
		efm = project_efm or ft_efm or default_efms[job.ft]
	end
	if not efm or efm == "" then
		return false
	end

	local old_cwd = nil
	if job.cwd and job.cwd ~= "" and job.cwd ~= vim.fn.getcwd() then
		old_cwd = vim.fn.getcwd()
		vim.api.nvim_set_current_dir(job.cwd)
	end

	if not pcall(vim.fn.setqflist, {}, "r", { lines = lines, efm = efm }) then
        return false
	end

	if old_cwd then
		vim.api.nvim_set_current_dir(old_cwd)
	end

	local qf = vim.fn.getqflist()
	local filtered = {}
	for _, item in ipairs(qf) do
		if item.valid == 1 then
			table.insert(filtered, item)
		end
	end
	return pcall(vim.fn.setqflist, filtered, "r")
end

return M
