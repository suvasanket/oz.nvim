local M = {}

--- You should not touch the config ever ---
--- Default config ---
local defaults = {
	-- Git
	oz_git = {
		win_type = "bot",
		mappings = {
			toggle_pick = "<C-P>",
			unpick_all = "<C-X>",
		},
	},

	-- all oz_term options
	oz_term = {
		efm = { "%f:%l:%c: %trror: %m" },
		root_prefix = "@",
	},

	-- Make
	oz_make = {
		override_make = false, -- override the default :make
		autosave_makeprg = true, -- auto save all the project scoped makeprg(:set makeprg=<cmd>)
		transient_mappings = {
			kill_job = "<C-X>",
			toggle_output = "<C-T>",
		},
	},

	-- Grep
	oz_grep = {
		override_grep = true, -- override the default :grep
	},

	integration = {
		-- oil integration
		oil = {
			entry_exec = {
				method = "term", -- |background, term|
				use_fullpath = true, -- false: only file or dir name will be used
				tail_prefix = ":", -- split LHS RHS
			},
			mappings = {
				entry_exec = "<C-G>",
				show_keybinds = "g?", -- override existing g?
			},
		},
	},
}

-- Setup function
function M.setup(opts)
	-- Merge user-provided options with defaults
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", defaults, opts)

	-- Initialize oz git
	if M.config.oz_git then
		require("oz.git").oz_git_usercmd_init(M.config.oz_git)
	end

	-- Initialize :Term
	if M.config.oz_term then
		require("oz.term").Term_init(M.config.oz_term)
	end

	-- Initialize :Make
	if M.config.oz_make then
		require("oz.make").oz_make_init(M.config.oz_make)
	end

	-- Initialize :Grep
	if M.config.oz_grep then
		require("oz.grep").oz_grep_init(M.config.oz_grep)
	end

	-- Initialize oil integration
	if M.config.integration.oil then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "oil",
			callback = function()
				require("oz.integration.oil").oil_init(M.config.integration.oil, M.config.mappings)
			end,
		})
	end
end

return M
