local M = {}

local mappings = require("oz.mappings")

--- Default configs:
local defaults = {
	mappings = {
		Term = "<leader>ao",
		TermBang = "<leader>at",
		Rerun = "<leader>ar",
	},

	-- Git
	oz_git = {
		remote_operation_exec_method = "background", -- |background,term|
		mappings = {
			toggle_pick = "<C-p>",
			unpick_all = "<C-S-p>",
		},
	},

	-- all oz_term options
	oz_term = {
		bufhidden_behaviour = "prompt", -- |prompt, hide, quit|
		mappings = {
			open_entry = "<cr>",
			add_to_quickfix = "<C-q>",
			open_in_compile_mode = "t",
			rerun = "r",
			quit = "q",
			show_keybinds = "g?",
		},
	},

	-- Make
	oz_make = {
		override_make = false, -- override the default :make
		autosave_makeprg = true, -- auto save all the project scoped makeprg(:set makeprg=<cmd>)
	},

	-- Grep
	oz_grep = {
		override_grep = true, -- override the default :grep
	},

	integration = {
		-- compile-mode integration
		compile_mode = {
			mappings = {
				open_in_oz_term = "t",
				show_keybinds = "g?",
			},
		},
		-- oil integration
		oil = {
			entry_exec = {
				method = "async", -- |async, term|
				use_fullpath = true, -- false: only file or dir name will be used
				lead_prefix = ":", -- this char will be used to define the pre and post of the entry
			},
			mappings = {
				term = "<global>",
				compile = "<global>",
				entry_exec = "<C-g>",
				show_keybinds = "g?", -- override existing g?
			},
		},
	},

	-- error_formats :help errorformat
	efm = {
		cache_efm = true,
	},
}

---check if start with cmd
---@param cmds table
---@return boolean
local function start_with_cmd(cmds)
	for i, arg in ipairs(vim.v.argv) do
		if arg == "-c" and vim.v.argv[i + 1] then
			for _, cmd in ipairs(cmds) do
				-- if vim.v.argv[i + 1] == cmd then
				if vim.startswith(vim.v.argv[i + 1], cmd) then
					return true
				end
			end
		end
	end
	return false
end

-- Setup function
function M.setup(opts)
	-- Merge user-provided options with defaults
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", defaults, opts)

	-- Initialize mappings
	vim.schedule(function()
		M.mappings_init()
	end)

	-- Initialize oz git
	if M.config.oz_git then
		if start_with_cmd({ "G", "Git" }) then
			require("oz.git").oz_git_usercmd_init(M.config.oz_git)
		else -- lazy
			vim.fn.timer_start(400, function()
				require("oz.git").oz_git_usercmd_init(M.config.oz_git)
			end)
		end
	end

	-- Initialize :Term
	if M.config.oz_term then
		if start_with_cmd({ "Term", "Term!" }) then
			require("oz.term").Term_init(M.config.oz_term)
		else -- lazy
			vim.fn.timer_start(700, function()
				require("oz.term").Term_init(M.config.oz_term)
			end)
		end
	end

	-- Initialize :Make
	if M.config.oz_make then
		if start_with_cmd({ "Make", "Make!" }) then
			require("oz.make").oz_make_init(M.config.oz_make)
		else -- lazy
			vim.fn.timer_start(500, function()
				require("oz.make").oz_make_init(M.config.oz_make)
			end)
		end
	end

	-- Initialize :Grep
	if M.config.oz_grep then
		if start_with_cmd({ "Grep", "Grep!" }) then
			require("oz.grep").oz_grep_init(M.config.oz_grep)
		else -- lazy
			vim.fn.timer_start(500, function()
				require("oz.grep").oz_grep_init(M.config.oz_grep)
			end)
		end
	end

	-- Initialize compile-mode integration
	if M.config.integration.compile_mode then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "compilation",
			callback = function()
				require("oz.integration.compile").compile_init(M.config.integration.compile_mode)
			end,
		})
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

	-- Initialize cache_efm
	if M.config.efm.cache_efm then
		vim.fn.timer_start(800, function()
			require("oz.qf").cache_efm()
		end)
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

	-- Rerunner
	if map_configs.Rerun then
		mappings.rerunner_init(map_configs.Rerun)
	end
end

return M
