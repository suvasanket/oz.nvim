local M = {}

local term = require("oz.term")
local mappings = require("oz.mappings")
local util = require("oz.util")

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
		cur_entry_async = true, -- false: run in oz_term instead of running async in background
		cur_entry_fullpath = true, -- false: only file or dir name will be used
		cur_entry_splitter = "$", -- this char will be used to define the pre and post of the entry
		mappings = {
			term = "<leader>av",
			compile = "<leader>ac",
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
	term.Term(M.config.oz_term)

	-- Initialize mappings
	M.mappings_init()

	-- Initialize compile-mode integration
	if M.config.compile_mode then
		require("oz.integration.compile").compile_init(M.config.compile_mode)
	end

	-- Initialize oil integration
	if M.config.oil then
		require("oz.integration.oil").oil_init(M.config.oil)
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
