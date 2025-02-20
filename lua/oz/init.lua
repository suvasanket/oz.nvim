local M = {}

local term = require("oz.term")
local mappings = require("oz.mappings")

-- Default configuration
local defaults = {
	mappings = {
		Term = "<leader>av",
		TermBang = "<leader>at",
		Compile = "<leader>ac",
		Rerun = "<leader>aa",
	},

    -- all oz_term options
	oz_term = {
		mappings = {
			open_entry = "<cr>",
			add_to_quickfix = "<C-q>",
			open_in_compile_mode = "t",
			rerun = "r",
			quit = "q",
			show_keybinds = "g?",
		},
	},

	-- compile-mode integration
	compile_mode = {
		mappings = {
			open_in_oz_term = "t",
			show_keybinds = "g?",
		},
	},

	-- oil integration
	oil = {
		CurEntryAsync = true, -- false: run in oz_term instead of running async in background
		CurEntryFullpath = true, -- false: only file or dir name will be used
		CurEntryDelimiter_Char = "$", -- this char will be used to define the pre and post of the entry
		mappings = {
			Term = "<leader>av",
			Compile = "<leader>ac",
			cur_entry_cmd = "<C-g>",
			show_keybinds = "g?", -- override existing g?
		},
	},
}

-- Setup function
function M.setup(opts)
	-- Merge user-provided options with defaults
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", defaults, opts)

	-- Initialize :Term
	term.Term({ keys = M.config.oz_term.mappings })

	-- Initialize mappings
	M.mappings_init()

	-- Initialize compile-mode integration
	if M.config.compile then
		local c = require("oz.integration.compile")
		c.compile_init({ keys = M.config.compile_mode.mappings })
	end

	-- Initialize oil integration
	if M.config.oil then
		local o = require("oz.integration.oil")
		o.oil_init({
			cur_entry_async = M.config.oil.CurEntryAsync,
			cur_entry_fullpath = M.config.oil.CurEntryFullpath,
			cur_entry_delimeter_char = M.config.oil.CurEntryDelimiter_Char,
			keys = M.config.oil.mappings,
		})
	end
end

function M.mappings_init()
	local map_configs = M.config.mappings

	-- TermBang key
	if map_configs.TermBang then
		mappings.termbangkey_init(map_configs.TermBang)
	end

	-- Term key
	if map_configs.Term then
		mappings.termkey_init(map_configs.Term)
	end

	-- Compile key
	if map_configs.Compile then
		mappings.compilekey_init(map_configs.Compile)
	end

	-- Rerunner
	if map_configs.Rerun then
		mappings.rerunner_init(map_configs.Rerun)
	end
end

return M
