local M = {}
local util = require("oz.util")
local log = require("oz.git.log")
local shell = require("oz.util.shell")

local get_selected_hash = log.get_selected_hash

function M.diff_working()
	local cur_hash = get_selected_hash()
	if #cur_hash > 0 then
		vim.cmd("Git diff " .. cur_hash[1])
	end
end

function M.diff_commit()
	local cur_hash = get_selected_hash()
	if #cur_hash > 0 then
		vim.cmd("Git diff " .. cur_hash[1] .. "~1 " .. cur_hash[1])
	end
end

function M.diff_branch()
	local cur_hash = get_selected_hash()
	if #cur_hash == 0 then
		return
	end

	local ok, branches =
		shell.run_command({ "git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes" })
	if not ok then
		return
	end

	vim.ui.select(branches, { prompt = "Select Branch to Diff against " .. cur_hash[1] }, function(choice)
		if choice then
			vim.cmd("Git diff " .. cur_hash[1] .. ".." .. choice)
		end
	end)
end

function M.diff_stash()
	local cur_hash = get_selected_hash()
	if #cur_hash == 0 then
		return
	end

	local ok, stashes = shell.run_command({ "git", "stash", "list" })
	if not ok then
		return
	end

	vim.ui.select(stashes, { prompt = "Select Stash to Diff against " .. cur_hash[1] }, function(choice)
		if choice then
			local stash_idx = choice:match("stash@%{%d+%}")
			if stash_idx then
				vim.cmd("Git diff " .. cur_hash[1] .. ".." .. stash_idx)
			end
		end
	end)
end

-- Diffview wrappers
function M.dv_open()
	local cur_hash = get_selected_hash()
	if #cur_hash > 0 then
		vim.cmd("DiffviewOpen " .. cur_hash[1])
	end
end

function M.dv_commit()
	local cur_hash = get_selected_hash()
	if #cur_hash > 0 then
		vim.cmd("DiffviewOpen " .. cur_hash[1] .. "^!")
	end
end

local diff_range_hash = {}
function M.diff_range()
	local hashes = get_selected_hash()
	if #hashes > 1 then
		vim.cmd("Git diff " .. hashes[1] .. ".." .. hashes[#hashes])
	elseif #hashes == 1 then
		vim.notify_once("press 'dp' on another to pick <end-commit-hash>.")
		util.tbl_insert(diff_range_hash, hashes[1])
		if #diff_range_hash == 2 then
			vim.cmd("Git diff " .. diff_range_hash[1] .. ".." .. diff_range_hash[#diff_range_hash])
			diff_range_hash = {}
		end
	end
end

function M.setup_keymaps(buf, key_grp, map_help_key)
	local options = {
		{
			title = "Native Diff",
			items = {
				{ key = "d", cb = M.diff_commit, desc = "Diff Commit (Show)" },
				{ key = "w", cb = M.diff_working, desc = "Diff Working Tree vs Commit" },
				{ key = "b", cb = M.diff_branch, desc = "Diff against Branch" },
				{ key = "s", cb = M.diff_stash, desc = "Diff against Stash" },
				{ key = "p", cb = M.diff_range, desc = "Diff Range (Pick 2)" },
			},
		},
	}

	if util.usercmd_exist("DiffviewOpen") then
		table.insert(options, {
			title = "Diffview",
			items = {
				{ key = "D", cb = M.dv_open, desc = "Open Diffview (Working)" },
				{ key = "C", cb = M.dv_commit, desc = "Open Diffview (Commit)" },
			},
		})
	end

	util.Map("n", "d", function()
		require("oz.util.help_keymaps").show_menu("Diff Actions", options)
	end, { buffer = buf, desc = "Diff Actions", nowait = true })

	util.Map("x", "d", M.diff_range, { buffer = buf, desc = "Diff range selection" })
end

return M
