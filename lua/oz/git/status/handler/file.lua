local M = {}
local util = require("oz.util")
local s_util = require("oz.git.status.util")

local function quote_and_join(args)
	local quoted = {}
	for _, arg in ipairs(args) do
		table.insert(quoted, string.format("%q", arg))
	end
	return table.concat(quoted, " ")
end

function M.stage()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local inline_diff = require("oz.git.status.inline_diff")
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" or mode == "V" or mode == "" then
		if inline_diff.stage_selection(bufnr) then
			return
		end
	elseif inline_diff.get_hunk_at_cursor(bufnr, cursor_line) then
		if inline_diff.stage_hunk_at_cursor(bufnr) then
			return
		end
	end

	local entries = s_util.get_file_under_cursor(true)
	util.exit_visual()
	local section = s_util.get_section_under_cursor()

	if #entries > 0 then
		-- Check if any of these files are expanded in inline diff
		-- For simplicity, we just handle the current line if it's one of the entries
		inline_diff.save_state_for_line(bufnr, cursor_line)

		s_util.run_n_refresh("Git add " .. quote_and_join(entries))

		-- Re-expand after refresh
		vim.defer_fn(function()
			inline_diff.refresh_if_needed(bufnr)
		end, 200)
	elseif section == "unstaged" then
		s_util.run_n_refresh("Git add -u")
	elseif section == "untracked" then
		util.set_cmdline(":Git add .")
	end
end

function M.unstage()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local inline_diff = require("oz.git.status.inline_diff")
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" or mode == "V" or mode == "" then
		if inline_diff.stage_selection(bufnr) then
			return
		end
	elseif inline_diff.get_hunk_at_cursor(bufnr, cursor_line) then
		if inline_diff.stage_hunk_at_cursor(bufnr) then
			return
		end
	end

	local entries = s_util.get_file_under_cursor(true)
	util.exit_visual()
	local section = s_util.get_section_under_cursor()

	if #entries > 0 then
		inline_diff.save_state_for_line(bufnr, cursor_line)

		s_util.run_n_refresh(string.format("Git reset -q HEAD -- %s", quote_and_join(entries)))

		vim.defer_fn(function()
			inline_diff.refresh_if_needed(bufnr)
		end, 200)
	elseif section == "staged" then
		s_util.run_n_refresh("Git reset -q")
	end
end

function M.discard()
	local entries = s_util.get_file_under_cursor(true)
	util.exit_visual()
	if #entries > 0 then
		local confirm_ans = util.prompt("Discard all the changes?", "&Yes\n&No", 2)
		if confirm_ans == 1 then
			s_util.run_n_refresh(string.format("Git restore %s -q", quote_and_join(entries)))
		end
	end
end

function M.untrack()
	local entries = s_util.get_file_under_cursor(true)
	util.exit_visual()
	if #entries > 0 then
		s_util.run_n_refresh("Git rm --cached " .. quote_and_join(entries))
	end
end

function M.rename()
	local file = s_util.get_file_under_cursor(true)[1]
	local new_name = util.UserInput("New name: ", file)
	if new_name then
		s_util.run_n_refresh(string.format("Git mv %s %s", file, new_name))
	end
end

function M.setup_keymaps(buf, key_grp)
	vim.keymap.set(
		{ "n", "x" },
		"s",
		M.stage,
		{ buffer = buf, desc = "Stage entry under cursor or selected entries.", silent = true }
	)
	-- unstage
	vim.keymap.set(
		{ "n", "x" },
		"u",
		M.unstage,
		{ buffer = buf, desc = "Unstage entry under cursor or selected entries.", silent = true }
	)
	-- discard
	vim.keymap.set(
		{ "n", "x" },
		"X",
		M.discard,
		{ buffer = buf, desc = "Discard entry under cursor or selected entries.", silent = true }
	)
	vim.keymap.set(
		{ "n", "x" },
		"D",
		M.untrack,
		{ buffer = buf, desc = "Untrack file or selected files.", silent = true }
	)
	vim.keymap.set("n", "R", M.rename, { buffer = buf, desc = "Rename the file under cursor.", silent = true })

	key_grp["File actions"] = { "s", "u", "D", "X", "R" }
end

return M
