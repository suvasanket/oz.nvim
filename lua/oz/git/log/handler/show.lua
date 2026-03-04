local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

local ns_id = vim.api.nvim_create_namespace("oz_git_commit_show")

local function setup_highlights()
	util.setup_hls({
		{ OzGitDiffHeader = { fg = "#c678dd", bold = true } },
		{ OzGitDiffHunkHeader = { fg = "#61afef", bold = true } },
		{ OzGitDiffAdd = { fg = "#98c379", bg = "#2d3b2d" } },
		{ OzGitDiffDel = { fg = "#e06c75", bg = "#3b2d2d" } },
		{ OzGitDiffContext = { fg = "#abb2bf" } },
		{ OzGitDiffFile = { fg = "#e5c07b", bold = true } },
		{ OzGitDiffSep = { fg = "#5c6370" } },
		{ OzGitCommitHash = { fg = "#e5c07b", bold = true } },
		{ OzGitCommitAuthor = { fg = "#61afef" } },
		{ OzGitCommitDate = { fg = "#98c379" } },
	})
end

---@param lnum number
function M.foldexpr(lnum)
	local levels = vim.b.oz_fold_levels
	if levels and levels[lnum] then
		return levels[lnum]
	end
	return "0"
end

local function get_file_under_cursor()
	local line = vim.api.nvim_get_current_line()
	-- Stat line:  lua/oz/git/log/handler/show.lua | 5 ++++-
	local stat_file = line:match("^%s*(.-)%s*|%s*%d+")
	if stat_file then
		return vim.trim(stat_file)
	end

	-- Diff header: diff --git a/lua/oz/git/log/handler/show.lua b/lua/oz/git/log/handler/show.lua
	local diff_file = line:match("^diff %-%-git a/(.-) b/")
	if diff_file then
		return diff_file
	end

	-- Inside a hunk or after diff header:
	-- --- a/lua/oz/git/log/handler/show.lua
	-- +++ b/lua/oz/git/log/handler/show.lua
	local minus_file = line:match("^%-%-%- a/(.*)")
	if minus_file and minus_file ~= "/dev/null" then
		return minus_file
	end
	local plus_file = line:match("^%+%+%+ b/(.*)")
	if plus_file and plus_file ~= "/dev/null" then
		return plus_file
	end

	-- If we are inside a hunk, look upwards for the filename.
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local lnum = cursor_pos[1]
	while lnum > 0 do
		local l = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]
		local f = l:match("^diff %-%-git a/(.-) b/")
		if f then
			return f
		end
		if l:match("^commit ") then
			break
		end -- reached start of commit
		lnum = lnum - 1
	end

	return nil
end

function M.open_file_at_cursor()
	local hash = vim.b.oz_commit_hash
	if not hash then
		return
	end
	local file = get_file_under_cursor()
	if file then
		require("oz.util.git").open_file_at_revision(hash, file)
	end
end

function M.pick_file_to_show()
	local hash = vim.b.oz_commit_hash
	if not hash then
		return
	end

	local root = require("oz.util.git").get_project_root()
	local ok, files = util.run_command({ "git", "ls-tree", "-r", "--name-only", "--full-name", hash }, root)
	if ok and #files > 0 then
		util.pick(files, {
			title = "Select file to view from " .. hash:sub(1, 7),
			on_select = function(choice)
				if choice then
					require("oz.util.git").open_file_at_revision(hash, choice)
				end
			end,
		})
	end
end

function M.show(hash)
	if not hash then
		local selected = log_util.get_selected_hash()
		if #selected == 0 then
			return
		end
		hash = selected[1]
	end

	local ok, lines = util.run_command({ "git", "show", "--format=fuller", "--stat", "--patch", "--no-color", hash })
	if not ok or #lines == 0 then
		util.Notify("Failed to get commit info", "error", "oz_git")
		return
	end

	setup_highlights()

	util.create_win("commit_show", {
		content = {},
		win_type = "tab",
		buf_name = "OzGitCommit:" .. hash:sub(1, 7),
		callback = function(buf_id, win_id)
			vim.bo[buf_id].ft = "oz_git_commit"
			vim.bo[buf_id].modifiable = true

			local final_lines = {}
			local highlights = {}
			local fold_levels = {}
			local section = "header"

			for i, line in ipairs(lines) do
				table.insert(final_lines, line)
				local ln = i - 1

				-- Determine Fold Level
				if line:match("^commit ") then
					section = "header"
					fold_levels[i] = ">1"
				elseif line:match("^diff %-%-git") then
					section = "diff"
					fold_levels[i] = ">1"
				elseif section == "header" and line:match("^ [^ ]") and line:find("|") then
					section = "stat"
					fold_levels[i] = ">1"
				elseif section == "stat" and (not line:match("^ [^ ]") or not line:find("|")) and line ~= "" and not line:find("changed") then
					-- End of stats if we see something else
                    -- But usually it just transitions to diff or end
				end

                if not fold_levels[i] then
                    fold_levels[i] = "1"
                end

				-- Highlights
				if line:match("^commit ") then
					table.insert(highlights, { ln, 0, -1, "OzGitCommitHash" })
				elseif
					line:match("^Author:")
					or line:match("^AuthorDate:")
					or line:match("^Commit:")
					or line:match("^CommitDate:")
				then
					local colon = line:find(":")
					table.insert(highlights, { ln, 0, colon, "OzEchoDef" })
					table.insert(highlights, {
						ln,
						colon + 1,
						-1,
						line:match("Date") and "OzGitCommitDate" or "OzGitCommitAuthor",
					})
				elseif line:match("^diff %-%-git") then
					table.insert(highlights, { ln, 0, -1, "OzGitDiffHeader" })
				elseif section == "stat" and line:match("^ [^ ]") and line:find("|") then
					local pipe = line:find("|")
					table.insert(highlights, { ln, 0, pipe - 1, "OzGitDiffFile" })
					local plus = line:find("%+")
					local minus = line:find("%-")
					if plus then
						table.insert(highlights, { ln, plus - 1, -1, "OzGitDiffAdd" })
					end
					if minus then
						table.insert(highlights, { ln, minus - 1, -1, "OzGitDiffDel" })
					end
				elseif section == "stat" and line:match("^ [^ ]") and line:find("changed") then
					table.insert(highlights, { ln, 0, -1, "OzGitDiffHeader" })
				elseif section == "diff" then
					if line:match("^@@") then
						table.insert(highlights, { ln, 0, -1, "OzGitDiffHunkHeader" })
					elseif line:match("^%+") and not line:match("^%+%+%+") then
						table.insert(highlights, { ln, 0, -1, "OzGitDiffAdd" })
					elseif line:match("^%-") and not line:match("^%-%-%-") then
						table.insert(highlights, { ln, 0, -1, "OzGitDiffDel" })
					elseif line:match("^index ") or line:match("^%-%-%- ") or line:match("^%+%+%+ ") then
						table.insert(highlights, { ln, 0, -1, "OzGitDiffSep" })
					end
				end
			end

			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, final_lines)
			vim.bo[buf_id].modifiable = false
			vim.bo[buf_id].bufhidden = "wipe"

			for _, hl in ipairs(highlights) do
				vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl[4], hl[1], hl[2], hl[3])
			end

			-- Folding Logic
			vim.api.nvim_buf_set_var(buf_id, "oz_fold_levels", fold_levels)
			vim.wo[win_id].foldmethod = "expr"
			vim.wo[win_id].foldexpr = "v:lua.require('oz.git.log.handler.show').foldexpr(v:lnum)"
            vim.wo[win_id].foldlevel = 1

			-- Keymaps
			local key_grp = {}
			vim.keymap.set("n", "q", function()
				util.win_close()
			end, { buffer = buf_id, silent = true, desc = "Close window" })
			vim.keymap.set("n", "<TAB>", "za", { buffer = buf_id, silent = true, desc = "Toggle fold" })
			vim.keymap.set("n", "<S-TAB>", "zA", { buffer = buf_id, silent = true, desc = "Toggle all folds" })

			vim.keymap.set(
				"n",
				"<CR>",
				M.open_file_at_cursor,
				{ buffer = buf_id, silent = true, desc = "Open file at cursor" }
			)
			vim.keymap.set(
				"n",
				"<leader>f",
				M.pick_file_to_show,
				{ buffer = buf_id, silent = true, desc = "Pick file to show" }
			)

			key_grp["Navigation"] = { "<TAB>", "<S-TAB>", "q" }
			key_grp["Actions"] = { "<CR>", "<leader>f" }

			local options = {
				{
					title = "Goto",
					items = {
						{
							key = "g",
							cb = function()
								vim.cmd("normal! gg")
							end,
							desc = "goto top of the buffer",
						},
						{
							key = "?",
							cb = function()
								util.show_maps({
									group = key_grp,
									no_empty = true,
								})
							end,
							desc = "Show all available keymaps",
						},
					},
				},
			}

			vim.keymap.set("n", "g", function()
				util.show_menu("Goto", options)
			end, { buffer = buf_id, desc = "Goto Actions", nowait = true, silent = true })

			vim.api.nvim_buf_set_var(buf_id, "oz_commit_hash", hash)
		end,
	})
end

return M
