local M = {}

local _highlights = {}

--- @type table<string, table>
M.oz_highlights = {
	OzActive = { link = "@attribute" },
	OzUrl = { underline = true, bold = true, sp = "#15F5BA" },
	OzNone = { bg = "NONE", ctermbg = "NONE" },
	OzEchoDef = { fg = "#606060" },
	OzCmdPrompt = { fg = "#757575" },
	OzGitStatusHeading = { link = "Title" },
}

--- Set a highlight group once.
--- @param name string Highlight group name.
--- @param val table Highlight values.
local function set_hl(name, val)
	if _highlights[name] then
		return
	end
	_highlights[name] = true
	vim.api.nvim_set_hl(0, name, val)
end

--- set hls
---@alias link_hl table<string, string>
---@alias def_hl table<string, table>
---@param hls (string|link_hl|def_hl)[]
function M.setup_hls(hls)
	for _, item in ipairs(hls) do
		if type(item) == "string" then
			local def = M.oz_highlights[item]
			if def then
				set_hl(item, def)
			end
		elseif type(item) == "table" then
			for name, val in pairs(item) do
				if type(val) == "string" then
					set_hl(name, { link = val })
				elseif type(val) == "table" then
					set_hl(name, val)
				end
			end
		end
	end
end

return M
