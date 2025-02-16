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
	compile = true,
	oil = true,
}

-- Setup function
function M.setup(opts)
	-- Merge user-provided options with defaults
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", defaults, opts)

	-- Initialize the plugin
	term.Term()
	M.mappings_init()
	if M.config.compile then
		local c = require("oz.integration.compile")
		c.compile_init()
	end

	if M.config.oil then
		local o = require("oz.integration.oil")
		if M.config.mappings.Term then
			o.oil_init(M.config.mappings.Term)
		end
		if M.config.mappings.Compile then
			o.oil_init(nil, M.config.mappings.Compile)
		end
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
