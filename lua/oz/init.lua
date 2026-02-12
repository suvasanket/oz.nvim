local M = {}

--- Default configs:
local defaults = {
	-- Git
	oz_git = {
        win_type = "botright",
		mappings = {
			toggle_pick = "<C-P>",
			unpick_all = "<C-S-P>",
		},
	},

	-- all oz_term options
	oz_term = {
		bufhidden_behaviour = "prompt", -- |prompt, hide, quit|
		mappings = {
			open_entry = "<cr>",
			add_to_quickfix = "<C-q>",
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

	-- Initialize oz git
	if M.config.oz_git then
		if start_with_cmd({ "G", "Git" }) then
			require("oz.git").oz_git_usercmd_init(M.config.oz_git)
		else -- lazy
			vim.fn.timer_start(10, function()
				require("oz.git").oz_git_usercmd_init(M.config.oz_git)
			end)
		end
	end

	-- Initialize :Term
	if M.config.oz_term then
		if start_with_cmd({ "Term", "Term!" }) then
			require("oz.term").Term_init(M.config.oz_term)
		else -- lazy
			vim.fn.timer_start(20, function()
				require("oz.term").Term_init(M.config.oz_term)
			end)
		end
	end

	-- Initialize :Make
	if M.config.oz_make then
		if start_with_cmd({ "Make", "Make!" }) then
			require("oz.make").oz_make_init(M.config.oz_make)
		else -- lazy
			vim.fn.timer_start(100, function()
				require("oz.make").oz_make_init(M.config.oz_make)
			end)
		end
	end

	-- Initialize :Grep
	if M.config.oz_grep then
		if start_with_cmd({ "Grep", "Grep!" }) then
			require("oz.grep").oz_grep_init(M.config.oz_grep)
		else -- lazy
			vim.fn.timer_start(50, function()
				require("oz.grep").oz_grep_init(M.config.oz_grep)
			end)
		end
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

return M
