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

		-- oz-term buffer specific binds
		oz_term = {
			open_entry = "<cr>",
			add_to_quickfix = "<C-q>",
			open_in_compile_mode = "t",
			rerun = "r",
			quit = "q",
			show_keybinds = "g?",
		},
		-- compile-mode buffer specific binds
		compile_mode = {
			open_in_oz_term = "t",
			show_keybinds = "g?",
		},
		-- oil buffer specific binds
		oil = {
			Term = "<leader>av",
			Compile = "<leader>ac",
            cur_entry_cmd = "<C-g>",
			show_keybinds = "g?", -- override existing g?
		},
	},
	compile = true,
	oil = true,
}

-- Setup function
function M.setup(opts)
	-- Merge user-provided options with defaults
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", defaults, opts)

	-- Initialize :Term
	term.Term({ keys = M.config.mappings.oz_term })

	-- Initialize mappings
	M.mappings_init()

	-- Initialize compile-mode integration
	if M.config.compile then
		local c = require("oz.integration.compile")
		c.compile_init({ keys = M.config.mappings.compile_mode })
	end

	-- Initialize oil integration
	if M.config.oil then
		local o = require("oz.integration.oil")
		o.oil_init({ keys = M.config.mappings.oil })
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
