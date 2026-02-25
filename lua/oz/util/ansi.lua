local M = {}

--- Map ANSI color codes to highlight groups
local ansi_to_hl = {
	["30"] = "Comment", -- Use Comment for "black" or dim text
	["31"] = "OzAnsiRed",
	["32"] = "OzAnsiGreen",
	["33"] = "OzAnsiYellow",
	["34"] = "OzAnsiBlue",
	["35"] = "OzAnsiMagenta",
	["36"] = "OzAnsiCyan",
	["37"] = "OzAnsiWhite",
	["2"] = "Comment", -- Dim
	-- Bold versions
	["1;30"] = "Comment",
	["1;31"] = "OzAnsiBoldRed",
	["1;32"] = "OzAnsiBoldGreen",
	["1;33"] = "OzAnsiBoldYellow",
	["1;34"] = "OzAnsiBoldBlue",
	["1;35"] = "OzAnsiBoldMagenta",
	["1;36"] = "OzAnsiBoldCyan",
	["1;37"] = "OzAnsiBoldWhite",
	-- Reset
	["0"] = nil,
}

--- Setup ANSI highlight groups if they don't exist
function M.setup_ansi_hls()
	local colors = {
		OzAnsiRed = { fg = "#f7768e" },
		OzAnsiGreen = { fg = "#9ece6a" },
		OzAnsiYellow = { fg = "#e0af68" },
		OzAnsiBlue = { fg = "#7aa2f7" },
		OzAnsiMagenta = { fg = "#bb9af7" },
		OzAnsiCyan = { fg = "#7dcfff" },
		OzAnsiWhite = { fg = "#c0caf5" },
	}

	for name, def in pairs(colors) do
		vim.api.nvim_set_hl(0, name, def)
		vim.api.nvim_set_hl(0, "OzAnsiBold" .. name:sub(7), vim.tbl_extend("force", def, { bold = true }))
	end
end

--- Parse ANSI escape codes from a list of lines
--- @param lines string[]
--- @return string[] stripped_lines
--- @return table[] highlights List of {line_idx, start_col, end_col, hl_group}
function M.parse_ansi(lines)
	local stripped_lines = {}
	local highlights = {}

	for i, line in ipairs(lines) do
		local stripped = ""
		local last_pos = 1
		local current_hl = nil
		local current_start = nil

		-- Match ANSI escape sequences: \27[...m
		while true do
			local s, e, cap = line:find("\27%[([%d;]*)m", last_pos)
			if not s then
				stripped = stripped .. line:sub(last_pos)
				if current_hl and current_start then
					table.insert(highlights, { i - 1, current_start, #stripped, current_hl })
				end
				break
			end

			-- Add text before the escape sequence
			local before = line:sub(last_pos, s - 1)
			stripped = stripped .. before

			if current_hl and current_start then
				table.insert(highlights, { i - 1, current_start, #stripped, current_hl })
			end

			if cap == "0" or cap == "" or cap == "m" then
				-- Reset
				current_hl = nil
				current_start = nil
			else
				current_hl = ansi_to_hl[cap] or "Normal"
				current_start = #stripped
			end

			last_pos = e + 1
		end
		table.insert(stripped_lines, stripped)
	end

	return stripped_lines, highlights
end

return M
