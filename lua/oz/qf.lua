local M = {}
local p = require("oz.caching")
local ft_efm_json = "ft_efm"

local custom_error_formats = {
	json = "%f:%l:%c: %m",
	java = "%A%f:%l: %m",
}

local function get_custom_efm(ft)
	local cached_efm = p.get_data(ft, ft_efm_json)
	cached_efm = cached_efm ~= "" and cached_efm or nil
	return cached_efm or custom_error_formats[ft] or "%f:%l:%c:%m"
end

local function filtered_lines(lines)
	local f_lines = {}
	for _, line in ipairs(lines) do
		if
			line:lower():match("error")
			or line:lower():match("warn")
			or line:lower():match("warning")
			or line:lower():match("err")
			or line:lower():match("issue")
			or line:lower():match("trace")
			or line:lower():match("file")
			or line:lower():match("stacktrace")
		then
			table.insert(f_lines, line)
		end
	end
	return f_lines
end

function M.capture_buf_to_qf(bufnr, ft)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("Invalid buffer number: " .. bufnr, vim.log.levels.ERROR)
		return
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local efm = get_custom_efm(ft)

	lines = filtered_lines(lines)

	vim.fn.setqflist({}, " ", {
		lines = lines,
		efm = efm,
	})
end

function M.capture_lines_to_qf(lines, ft)
	local f_lines = filtered_lines(lines)

	local efm = get_custom_efm(ft)

	vim.fn.setqflist({}, " ", {
		lines = f_lines,
		efm = efm,
	})
end

-- initialize chaching
function M.cache_efm()
	vim.api.nvim_create_autocmd("OptionSet", {
		pattern = "errorformat",
		callback = function()
			local errorformat = vim.o.errorformat
			local ft = vim.bo.ft
			if ft then
				p.set_data(ft, errorformat, ft_efm_json)
			end
		end,
	})
end

return M
