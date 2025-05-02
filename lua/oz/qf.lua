local M = {}
local p = require("oz.caching")
local ft_efm_json = "ft_efm"

-- efm patterns
local custom_error_formats = {
	json = "%f:%l:%c: %m",
	java = "%A%f:%l: %m",
}

-- regex patterns
local language_patterns = {
	python = {
		file_line_pattern = '^%s*File%s+"([^"]+)",%s+line%s+(%d+)',
		continuation_pattern = function(line)
			return line:match("^%S") or line:match("^%a+Error:")
		end,
	},
	c = {
		file_line_pattern = "^(.-):(%d+):(%d+):%s*(.*)$",
		continuation_pattern = function()
			return false
		end,
	},
	rust = {
		file_line_pattern = "^%s*-->%s+([^:]+):(%d+):(%d+)",
		continuation_pattern = function(line)
			return line:match("^%s") or line:match("^error:")
		end,
	},
}

--- parse lines funciton
---@param lines table
---@param filetype string
---@return table
local function parse_lines(lines, filetype)
	local cached_efm = p.get_data(filetype, ft_efm_json)
	if cached_efm or custom_error_formats[filetype] then
		local efm_format = cached_efm or custom_error_formats[filetype]
		local opts = { lines = lines, efm = efm_format }
		-- print("oz: using cached efm: " .. efm_format)
		vim.fn.setqflist({}, "r", opts)
		local qflist = vim.fn.getqflist()
		return qflist
	elseif language_patterns[filetype] then
		local patterns = language_patterns[filetype] or language_patterns["python"]

		local results = {}
		local prev = nil

		for _, line in ipairs(lines) do
			local filename, lnum, col, text = line:match(patterns.file_line_pattern)
			if filename then
				prev = {
					filename = filename,
					lnum = tonumber(lnum),
					col = col and tonumber(col) or 0,
					text = text or "",
				}
				table.insert(results, prev)
			elseif prev and patterns.continuation_pattern(line) then
				local clean_line = line:gsub("^%s+", "")
				prev.text = (prev.text ~= "" and prev.text .. " " or "") .. clean_line
				prev = nil
			end
		end

		return results
	else
		return {}
	end
end

local keywords = { "error", "warn", "warning", "err", "issue", "trace", "file", "stacktrace" }

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

-- lines -> qf
--- capture lines to quickfix
---@param lines table
---@param ft string
---@param if_error boolean|nil
function M.capture_lines_to_qf(lines, ft, if_error)
	if not if_error then
		if_error = lines_contains_keyword(lines, keywords)
	end

	if if_error then
		local parsed = parse_lines(lines, ft)

		if #parsed > 0 then
			vim.fn.setqflist(parsed, "r")
		end
	end
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
