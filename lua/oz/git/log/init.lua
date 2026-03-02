local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

M.log_win = nil
M.log_buf = nil
local commit_log_lines = nil

M.log_level = 1
M.comming_from = nil
M.grab_hashs = {}
M.state = {}
local user_set_args = nil

-- get selected or current SHA under cursor
---@return table
function M.get_selected_hash()
	return log_util.get_selected_hash()
end

-- highlight
local function log_buf_hl(buf_id, raw_lines)
	local git_state = require("oz.util.git").get_git_state(M.state.cwd)
	log_util.apply_log_highlights(buf_id, raw_lines, git_state, M.log_win)
end

local function generate_content(level, args)
	if args and #args > 0 then
		user_set_args = args
	else
		user_set_args = user_set_args or { "--all" }
	end
	return log_util.generate_content(level, M.state.cwd, user_set_args)
end

function M.refresh_buf(passive)
	if not passive then
		commit_log_lines = generate_content(M.log_level)
	end

	if M.log_buf and vim.api.nvim_buf_is_valid(M.log_buf) then
		log_buf_hl(M.log_buf, commit_log_lines)
	end
end

-- commit log
---@param opts table|nil
---@param args table|nil
function M.commit_log(opts, args)
	if opts then
		M.comming_from = opts.from
		M.log_level = opts.level or M.log_level
	end
	local win_type = (opts and opts.win_type) or require("oz.git").user_config.win_type or "tab"
	M.state.cwd = vim.fn.getcwd():match("(.*)/%.git") or vim.fn.getcwd()

	vim.cmd("lcd " .. M.state.cwd)
	commit_log_lines = generate_content(M.log_level, args)

	util.create_win("log", {
		content = {},
		win_type = win_type,
		buf_name = "OzGitLog",
		callback = function(buf_id, win_id)
			M.log_buf, M.log_win = buf_id, win_id
			vim.cmd([[setlocal ft=oz_git signcolumn=no listchars= nonumber norelativenumber nowrap nomodifiable bufhidden=wipe]])
			vim.opt_local.fillchars:append({ eob = " " })
			log_buf_hl(buf_id, commit_log_lines)
			vim.fn.timer_start(100, function() require("oz.git.log.keymaps").keymaps_init(buf_id) end)
		end,
	})
end

return M
