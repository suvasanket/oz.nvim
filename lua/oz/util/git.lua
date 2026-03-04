--- @class oz.util.git
local M = {}
local util = require("oz.util")

--- Check if a path is inside a Git work tree.
--- @param path? string Optional path to check.
--- @return boolean True if inside a Git work tree.
function M.if_in_git(path)
	local ok, output = util.run_command({ "git", "rev-parse", "--is-inside-work-tree" }, path)

	if ok and output[1] then
		return output[1]:find("true") ~= nil
	end
	return false
end

--- Get the Git project root.
--- @return string|nil The Git project root path.
function M.get_project_root()
	local ok, path = util.run_command({ "git", "rev-parse", "--show-toplevel" })
	if ok and #path ~= 0 then
		return vim.trim(table.concat(path, " "))
	end
	return nil
end

--- Get a list of Git branches.
--- @param arg? {loc?: boolean, rem?: boolean} Optional filters for local or remote branches.
--- @return string[] A list of branch names.
function M.get_branch(arg)
	local ref
	if arg and arg.loc then
		ref = "refs/heads"
	elseif arg and arg.rem then
		ref = "refs/remotes"
	else
		ref = "refs/heads refs/remotes"
	end
	return util.shellout_tbl(string.format("git for-each-ref --format=%%(refname:short) %s", ref))
end

--- Open a file at a specific revision in a new buffer.
--- @param commit_hash string The commit hash.
--- @param file_path string The file path.
function M.open_file_at_revision(commit_hash, file_path)
	local root = M.get_project_root()
	local ok, content = util.run_command({ "git", "show", commit_hash .. ":" .. file_path }, root)
	if ok then
		util.create_win("oz_git_log_file", {
			content = content,
			win_type = "tab",
			buf_name = string.format("%s @ %s", file_path, commit_hash:sub(1, 7)),
			callback = function(buf_id, win_id)
				local ft = vim.filetype.match({ filename = file_path })
				if ft then
					vim.api.nvim_set_option_value("filetype", ft, { buf = buf_id })
				end
				vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_id })
				vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf_id })
				vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
				vim.api.nvim_set_option_value("number", true, { win = win_id })
				vim.api.nvim_set_option_value("relativenumber", false, { win = win_id })
				vim.api.nvim_set_option_value("signcolumn", "no", { win = win_id })
				vim.api.nvim_set_option_value("foldcolumn", "0", { win = win_id })

				vim.keymap.set(
					"n",
					"q",
					"<cmd>close<cr>",
					{ buffer = buf_id, desc = "Close buffer", silent = true }
				)
			end,
		})
	else
		util.Notify(
			"Could not show file "
				.. file_path
				.. "\nRoot: "
				.. (root or "N/A")
				.. "\nError: "
				.. table.concat(content or {}, "\n"),
			"error",
			"oz_git"
		)
	end
end

--- Check if a string contains something that looks like a Git hash.
--- @param text string The string to check.
--- @return boolean True if it contains a hash.
function M.str_contains_hash(text)
	if type(text) ~= "string" then
		return false
	end

	for hex_sequence in text:gmatch("(%x+)") do
		local len = #hex_sequence
		if (len >= 7 and len <= 12) or len == 40 or len == 64 then
			return true
		end
	end
	return false
end

--- Get the current state of the Git repository.
--- @param cwd? string The working directory.
--- @return {operation: string, hash: string|nil} | nil
function M.get_git_state(cwd)
	local git_dir = util.shellout_str("git rev-parse --git-dir", cwd)
	if not git_dir or git_dir == "" then return nil end

	local paths = {
		{ path = git_dir .. "/BISECT_LOG", op = "bisect", head = "HEAD" },
		{ path = git_dir .. "/CHERRY_PICK_HEAD", op = "cherry-pick", head = "CHERRY_PICK_HEAD" },
		{ path = git_dir .. "/MERGE_HEAD", op = "merge", head = "MERGE_HEAD" },
		{ path = git_dir .. "/REBASE_HEAD", op = "rebase", head = "REBASE_HEAD" },
		{ path = git_dir .. "/rebase-merge", op = "rebase", head = "HEAD" },
		{ path = git_dir .. "/rebase-apply", op = "rebase", head = "HEAD" },
	}

	for _, p in ipairs(paths) do
		if vim.fn.filereadable(p.path) == 1 or vim.fn.isdirectory(p.path) == 1 then
			local hash = p.head and util.shellout_str("git rev-parse --short " .. p.head, cwd) or nil
			local state = { operation = p.op, hash = hash }

			if p.op == "bisect" then
				local bisect_map = {}
				local ok, lines = util.run_command({ "git", "for-each-ref", "--format=%(objectname) %(refname)", "refs/bisect/" }, cwd)
				if ok then
					for _, line in ipairs(lines) do
						local full_sha, ref = line:match("^(%x+) (.*)")
						if full_sha and ref then
							local marker = nil
							if ref:find("refs/bisect/bad") then
								marker = "B"
							elseif ref:find("refs/bisect/good") then
								marker = "G"
							elseif ref:find("refs/bisect/skipped") then
								marker = "S"
							end
							if marker then
								bisect_map[full_sha:sub(1, 7)] = marker
							end
						end
					end
				end
				state.bisect_map = bisect_map
			end

			return state
		end
	end
	return nil
end

return M
