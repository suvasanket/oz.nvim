local M = {}

local keywords = { "error", "warn", "warning", "err", "issue", "trace", "file", "stacktrace" }

local default_efms = {
	python = '%E  File "%f"\\, line %l,%C%m,%Z%m',
	c = "%f:%l:%c: %m,%f:%l: %m",
	cpp = "%f:%l:%c: %m,%f:%l: %m",
    rust = [[%Eerror: %m,%Eerror[E%n]: %m,%Z %\\+--> %f:%l:%c]],
	go = "%f:%l:%c: %m",
	java = "%A%f:%l: %m,%-Z%p^,%-C%.%#",
	typescript = "%f(%l\\,%c): %m,%f(%l\\,%c): %t%*[^:]: %m",
	javascript = "%f(%l\\,%c): %m",
	lua = "%f:%l: %m",
	ruby = "%E%f:%l: %m",
	php = "%EParse error: %m in %f on line %l",
}

--- check if str cotains
---@param lines table
---@param words table
---@return boolean
local function lines_contains_keyword(lines, words)
	for _, line in ipairs(lines) do
		for _, keyword in ipairs(words) do
			if line:lower():match(keyword) then
				return true
			end
		end
	end
	return false
end

--- capture lines to quickfix
---@param lines table
---@param ft string
---@param custom_efm table|nil
---@param if_error boolean|nil
---@param fallback_efm string|nil
---@param cwd string|nil
function M.capture_lines_to_qf(lines, ft, custom_efm, if_error, fallback_efm, cwd)
	if not if_error then
		if_error = lines_contains_keyword(lines, keywords)
	end

	if if_error then
		local efm = (custom_efm or {})[ft] or default_efms[ft] or fallback_efm or vim.o.errorformat
		if not efm or efm == "" then
			return
		end

		local old_cwd
		if cwd and cwd ~= "" and cwd ~= vim.fn.getcwd() then
			old_cwd = vim.fn.getcwd()
			vim.api.nvim_set_current_dir(cwd)
		end

		vim.fn.setqflist({}, "r", { lines = lines, efm = efm })

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
		vim.fn.setqflist(filtered, "r")
	end
end

return M
