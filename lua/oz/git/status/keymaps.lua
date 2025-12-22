local M = {}
local status = require("oz.git.status")
local util = require("oz.util")
local show_map = require("oz.util.help_keymaps")
local s_util = require("oz.git.status.util")
local g_util = require("oz.git.util")
local wizard = require("oz.git.wizard")
local handle = require("oz.git.status.handler")

local refresh = status.refresh_status_buf
local state = status.state
local buf_id = nil

local function handle_show_help()
	local user_mappings = require("oz.git").user_config.mappings -- Get mappings at time of call
	show_map.show_maps({
		group = {
			["Pick mappings"] = { user_mappings.toggle_pick, user_mappings.unpick_all, "a", "i" },
			["Commit mappings[c]"] = { "cc", "ca", "ce", "c<Space>", "cw", "cu" },
			["Diff mappings[d]"] = { "dd", "dc", "dm", "db" },
			["Tracking related mappings"] = { "s", "u", "K", "X" },
			["Goto mappings[g]"] = { "gI", "gu", "gs", "gU", "gz", "gl", "gL", "g<Space>", "g?" }, -- Added gL
			["Remote mappings[M]"] = { "Ma", "Md", "Mr", "MM" }, -- Added mP
			["Quick actions"] = { "grn", "<Tab>", "<CR>", "I", "<C-R>", "q" }, -- Added refresh, quit, pull
			["Conflict resolution mappings[x]"] = { "xo", "xc", "xp" },
			["Stash mappings[z]"] = { "zz", "za", "zp", "zd", "z<Space>", "z" },
			["Branch mappings[b]"] = { "bn", "bd", "bu", "bU" },
			["Push/Pull mappings"] = { "p", "P", "f" },
			["Merge mappings[m]"] = { "mm", "ml", "ma", "ms", "me", "mq", "m<Space>" },
			["Rebase mappings[r]"] = { "rr", "ri", "rl", "ra", "rq", "rk", "re", "r<Space>" },
			["Reset mappings[U]"] = { "UU", "Up", "Uu", "Us", "Ux", "Uh", "Um" },
		},
		no_empty = true,
		subtext = { "[<*> represents the key is actionable for the entry under cursor.]" },
	})
end

-- Helper to map specific help keys
local function map_help_key(key, title)
	util.Map({ "n", "x" }, key, function()
		show_map.show_maps({ key = key, title = title, sub_help_buf = true })
	end, { buffer = buf_id })
end

-- =======================
--  Keymap Definitions
-- =======================
function M.keymaps_init(buf)
	buf_id = buf

	-- quit
	util.Map("n", "q", handle.other.quit, { buffer = buf_id, desc = "Close git status buffer." })

	-- tab (toggle)
	util.Map("n", "<tab>", handle.other.tab, { buffer = buf_id, desc = "Toggle headings / inline file diff. <*>" })

	-- refresh
	util.Map("n", "<C-r>", refresh, { buffer = buf_id, desc = "Refresh status buffer." })

	-- stage
	util.Map(
		{ "n", "x" },
		"s",
		handle.add.stage,
		{ buffer = buf_id, desc = "Stage entry under cursor or selected entries. <*>" }
	)

	-- unstage
	util.Map(
		{ "n", "x" },
		"u",
		handle.add.unstage,
		{ buffer = buf_id, desc = "Unstage entry under cursor or selected entries. <*>" }
	)

	-- discard
	util.Map(
		{ "n", "x" },
		"X",
		handle.add.discard,
		{ buffer = buf_id, desc = "Discard entry under cursor or selected entries. <*>" }
	)

	-- untrack
	util.Map({ "n", "x" }, "K", handle.add.untrack, { buffer = buf_id, desc = "Untrack file or selected files. <*>" })

	-- rename
	util.Map("n", "grn", handle.other.rename, { buffer = buf_id, desc = "Rename file or branch under cursor. <*>" })

	-- [z]Stash mappings --TODO add stash branch
	-- stash apply
	util.Map("n", "za", handle.other.stash_apply, { buffer = buf_id, desc = "Apply stash under cursor. <*>" })
	-- stash pop
	util.Map("n", "zp", handle.other.stash_pop, { buffer = buf_id, desc = "Pop stash under cursor. <*>" })
	-- stash drop
	util.Map("n", "zd", handle.other.stash_drop, { buffer = buf_id, desc = "Drop stash under cursor. <*>" })
	-- :Git stash
	util.Map(
		"n",
		"z<space>",
		":Git stash ",
		{ silent = false, buffer = buf_id, desc = "Populate cmdline with :Git stash." }
	)
	-- stash save
	util.Map("n", "zz", function()
		local input = util.inactive_input(":Git stash", " save ")
		if input then
			s_util.run_n_refresh("Git stash" .. input)
		end
	end, { buffer = buf_id, desc = "Stash save optionally add a message." })

	-- commit map
	util.Map("n", "cc", handle.commit.create, { buffer = buf_id, desc = "Create a commit" })
	-- commit ammend --no edit
	util.Map("n", "ce", handle.commit.amend_no_edit, { buffer = buf_id, desc = "Ammend with --no-edit." })
	-- commit amend
	util.Map("n", "ca", handle.commit.amend, { buffer = buf_id, desc = "Ammend previous commit." })
	-- commit undo
	util.Map("n", "cu", handle.commit.undo, { buffer = buf_id, desc = "Undo last commit." })
	-- G commit cmdline
	util.Map(
		"n",
		"c<space>",
		":Git commit ",
		{ silent = false, buffer = buf_id, desc = "Populate cmdline with :Git commit." }
	)
	-- commit wip
	util.Map("n", "cw", ":Gcw", { silent = false, buffer = buf_id, desc = "Populate cmdline with :Gcw" })

	-- open current entry / switch branch
	util.Map(
		"n",
		"<cr>",
		handle.other.enter_key,
		{ buffer = buf_id, desc = "open entry under cursor / switch branches. <*>" }
	)

	-- [g]oto mode
	-- log
	util.Map("n", "gl", handle.other.goto_log, { buffer = buf_id, desc = "goto commit logs." })
	util.Map(
		"n",
		"gL",
		handle.other.goto_log_context,
		{ buffer = buf_id, desc = "goto commit logs for file/branch. <*>" }
	)
	-- :Git
	util.Map("n", "g<space>", ":Git ", { silent = false, buffer = buf_id, desc = "Populate cmdline with :Git." })
	-- goto sections
	util.Map("n", "gu", function()
		g_util.goto_str("Changes not staged for commit:")
	end, { buffer = buf_id, desc = "goto unstaged changes section." })
	util.Map("n", "gs", function()
		g_util.goto_str("Changes to be committed:")
	end, { buffer = buf_id, desc = "goto staged for commit section." })
	util.Map("n", "gU", function()
		g_util.goto_str("Untracked files:")
	end, { buffer = buf_id, desc = "goto untracked files section." })
	util.Map("n", "gz", function()
		g_util.goto_str("Stash list:")
	end, { buffer = buf_id, desc = "goto stashlist section." })
	-- Add to gitignore
	util.Map(
		{ "n", "x" },
		"gI",
		handle.other.goto_gitignore,
		{ buffer = buf_id, desc = "Add file or dir to .gitignore. <*>" }
	)

	-- [d]iff mode
	util.Map("n", "dd", handle.diff.file_changes, { buffer = buf_id, desc = "Diff file changes. <*>" })
	util.Map("n", "dc", handle.diff.file_history, { buffer = buf_id, desc = "Diff file history or stash. <*>" })
	if util.usercmd_exist("DiffviewOpen") or util.usercmd_exist("DiffviewFileHistory") then -- only diffview keymaps
		util.Map("n", "dm", handle.diff.remote, { buffer = buf_id, desc = "Diff between local and remote branch. <*>" })
		util.Map("n", "db", handle.diff.branch, { buffer = buf_id, desc = "Diff between branches. <*>" })
	end

	-- Merge/Conflict helper
	if state.in_conflict then
		-- Notifications about conflict state
		if wizard.on_conflict_resolution_complete then
			vim.notify_once(
				"Conflict resolution marked as complete. Stage changes and commit.",
				vim.log.levels.INFO,
				{ title = "oz_git", timeout = 3000 }
			)
		else
			vim.notify_once(
				"File has conflicts. Press 'xo' (manual) or 'xp' (Diffview) to resolve.",
				vim.log.levels.INFO,
				{ title = "oz_git", timeout = 3000 }
			)
		end
		-- start resolution
		util.Map(
			"n",
			"xo",
			handle.other.conflict_start_manual,
			{ buffer = buf_id, desc = "Start manual conflict resolution." }
		)
		-- complete (manual)
		util.Map(
			"n",
			"xc",
			handle.other.conflict_complete,
			{ buffer = buf_id, desc = "Complete manual conflict resolution." }
		)
		-- diffview resolve
		if util.usercmd_exist("DiffviewOpen") then
			util.Map(
				"n",
				"xp",
				handle.other.conflict_diffview,
				{ buffer = buf_id, desc = "Open Diffview for conflict resolution." }
			)
		end
	end

	-- Pick Mode
	local user_mappings = require("oz.git").user_config.mappings -- Ensure this is available
	util.Map(
		"n",
		user_mappings.toggle_pick,
		handle.pick.toggle_pick,
		{ nowait = true, buffer = buf_id, desc = "Pick/unpick file/branch/stash. <*>" }
	)
	util.Map(
		"n",
		{ "a", "i" },
		handle.pick.edit_picked,
		{ nowait = true, buffer = buf_id, desc = "Enter cmdline to edit picked." }
	)
	util.Map(
		"n",
		user_mappings.unpick_all,
		handle.pick.discard_picked,
		{ nowait = true, buffer = buf_id, desc = "Discard picked entries." }
	)

	-- Remote mappings
	util.Map("n", "MM", "<cmd>Git remote -v<cr>", { buffer = buf_id, desc = "Remote list." })
	util.Map("n", "Ma", handle.remote.add_update, { buffer = buf_id, desc = "Add or update remotes." })
	util.Map("n", "Md", handle.remote.remove, { buffer = buf_id, desc = "Remove remote. <*>" })
	util.Map("n", "Mr", handle.remote.rename, { buffer = buf_id, desc = "Rename remote. <*>" })

	-- push / pull
	util.Map(
		"n",
		"p",
		handle.push_pull.pull,
		{ buffer = buf_id, desc = "Git pull or pull from branch under cursor. <*>" }
	)
	util.Map(
		"n",
		"P",
		handle.push_pull.push,
		{ buffer = buf_id, desc = "Git push or push to branch under cursor. <*>" }
	)
	util.Map(
		"n",
		"f",
		handle.push_pull.fetch,
		{ buffer = buf_id, desc = "Git push or push to branch under cursor. <*>" }
	)

	-- [B]ranch mappings
	util.Map("n", "bn", handle.branch.new, { buffer = buf_id, desc = "Create a new branch. <*>" })
	util.Map("n", "bd", handle.branch.delete, { buffer = buf_id, desc = "Delete branch under cursor. <*>" })
	util.Map(
		"n",
		"bu",
		handle.branch.set_upstream,
		{ buffer = buf_id, desc = "Set upstream for branch under cursor. <*>" }
	)
	util.Map(
		"n",
		"bU",
		handle.branch.unset_upstream,
		{ buffer = buf_id, desc = "Unset upstream for branch under cursor. <*>" }
	)

	-- [M]erge mappings
	util.Map(
		"n",
		"mm",
		handle.other.merge_branch,
		{ buffer = buf_id, desc = "Start merge with branch under cursor. <*>" }
	)
	util.Map("n", "ml", function()
		s_util.run_n_refresh("Git merge --continue")
	end, { buffer = buf_id, desc = "Merge continue." })
	util.Map("n", "ma", function()
		s_util.run_n_refresh("Git merge --abort")
	end, { buffer = buf_id, desc = "Merge abort." })
	util.Map("n", "ms", function()
		handle.other.merge_branch("--squash")
	end, { buffer = buf_id, desc = "Merge with squash." })
	util.Map("n", "me", function()
		handle.other.merge_branch("--no-commit")
	end, { buffer = buf_id, desc = "Merge with no-commit." })
	util.Map("n", "mq", function()
		handle.other.merge_branch("--quit")
	end, { buffer = buf_id, desc = "Merge quit." })
	util.Map(
		"n",
		"m<space>",
		":Git merge ",
		{ silent = false, buffer = buf_id, desc = "Populate cmdline with Git merge." }
	)

	-- [R]ebase mappings
	util.Map(
		"n",
		"rr",
		handle.other.rebase_branch,
		{ buffer = buf, desc = "Rebase branch under cursor with provided args. <*>" }
	)
	util.Map("n", "ri", function()
		local branch_under_cursor = s_util.get_branch_under_cursor()
		if branch_under_cursor then
			s_util.run_n_refresh("Git rebase -i " .. branch_under_cursor)
		end
	end, { buffer = buf, desc = "Start interactive rebase with branch under cursor. <*>" })
	util.Map("n", "rl", function()
		s_util.run_n_refresh("Git rebase --continue")
	end, { buffer = buf, desc = "Rebase continue." })
	util.Map("n", "ra", function()
		s_util.run_n_refresh("Git rebase --abort")
	end, { buffer = buf, desc = "Rebase abort." })
	util.Map("n", "rq", function()
		s_util.run_n_refresh("Git rebase --quit")
	end, { buffer = buf, desc = "Rebase quit." })
	util.Map("n", "rk", function()
		s_util.run_n_refresh("Git rebase --skip")
	end, { buffer = buf, desc = "Rebase skip." })
	util.Map("n", "re", function()
		s_util.run_n_refresh("Git rebase --edit-todo")
	end, { buffer = buf, desc = "Rebase edit todo." })
	util.Map(
		"n",
		"r<space>",
		":Git rebase ",
		{ silent = false, buffer = buf_id, desc = "Populate cmdline with :Git rebase." }
	)

	-- [R]eset mappings
	util.Map({ "n", "x" }, "UU", handle.other.reset, { buffer = buf, desc = "Reset file/branch. <*>" })
	util.Map("n", "Up", handle.other.undo_orig_head, { buffer = buf, desc = "Reset origin head." })
	util.Map("n", "Us", function()
		handle.other.reset("--soft")
	end, { buffer = buf, desc = "Reset soft." })
	util.Map("n", "Um", function()
		handle.other.reset("--mixed")
	end, { buffer = buf, desc = "Reset mixed." })
	util.Map("n", "Uh", function()
		local confirm_ans = util.prompt("Do really really want to Git reset --hard ?", "&Yes\n&No", 2)
		if confirm_ans == 1 then
			handle.other.reset("--hard")
		end
	end, { buffer = buf, desc = "Reset hard(danger)." })

	-- open reflog
	util.Map("n", "I", "<cmd>Git reflog<cr>", { buffer = buf, desc = "Open reflog" })

	-- help
	util.Map("n", "g?", handle_show_help, { buffer = buf_id, desc = "Show all availble keymaps." })
	map_help_key("M", "Remote mappings")
	map_help_key("c", "Commit mappings")
	map_help_key("z", "Stash mappings")
	map_help_key("d", "Diff mappings")
	map_help_key("b", "Branch mappings")
	map_help_key("m", "Merge mappings")
	map_help_key("r", "Rebase mappings")
	map_help_key("x", "Conflict resolution mappings")
	map_help_key("U", "Reset mappings")
end -- End of M.keymaps_init

return M
