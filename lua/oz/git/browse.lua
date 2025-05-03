local M = {}
local util = require("oz.util")
local g_util = require("oz.git.util")
local shell = require("oz.util.shell")

local run_command = function(tbl, cwd)
	local ok, out = shell.run_command(tbl, cwd)
	return ok, vim.trim(table.concat(out, "\n"))
end

local function get_relative_path(target_path, cur_remote, branch, git_root)
	local clean_path_ok, clean_target_path = run_command({
		"git",
		"ls-tree",
		"--name-only",
		"-r",
		string.format("%s/%s", cur_remote, branch),
		"--",
		target_path,
	}, git_root)
	if clean_path_ok then
		if clean_target_path ~= "" then
			return clean_target_path
		end
	end
	return false
end

-- Main function to browse the git repository file/directory
function M.browse(target_path)
	target_path = target_path or vim.fn.expand("%:p")
	if target_path == "" then
		return
	end
	target_path = vim.fn.fnamemodify(target_path, ":p") -- Ensure absolute path

	-- 2. get git root
	local git_root = g_util.get_project_root()

	if not git_root or git_root == "" then
		util.Notify("Not inside a Git repository or git command failed: " .. git_root, "error", "oz_git")
		return
	end

	-- 3. get current branch
	local ok_branch, cur_local_branch = run_command({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, git_root)
	if not ok_branch or cur_local_branch == "HEAD" then
		util.Notify("Could not get the current branch.", "error", "oz_git")
	end
	local cur_remote_branch_ref =
		shell.shellout_str(string.format("git rev-parse --abbrev-ref %s@{u}", cur_local_branch))
	local cur_remote_branch = cur_remote_branch_ref:match("[^/]+$")

	-- 4. get remote url
	local ok_remote, remote_url
	local ok_remote_name, cur_remote =
		run_command({ "git", "config", "--get", string.format("branch.%s.remote", cur_local_branch) })
	if ok_remote_name then
		ok_remote, remote_url = run_command({ "git", "remote", "get-url", cur_remote }, git_root)
		if not ok_remote then
			util.Notify('Could not get remote URL for "origin". ' .. remote_url, "error", "oz_git")
			return
		end
	end

	-- 5. Calculate the relative path from git root
	local clean_git_root = git_root:gsub("/$", ""):gsub("\\$", "")

	local file_exist_in_remote = get_relative_path(target_path, cur_remote, cur_remote_branch, git_root)
	if not file_exist_in_remote then
		util.Notify("Provided entry is not available in remote.", "error", "oz_git")
		return
	end
	local relative_path = target_path:match("^" .. vim.pesc(clean_git_root) .. "(.*)$")
	-- local relative_path = target_path:gsub("^" .. vim.fn.escape(clean_git_root, "/\\"), "") -- Escape path chars for pattern
	relative_path = relative_path:gsub("^[/\\]", "") -- Remove leading slash/backslash
	relative_path = relative_path:gsub("\\", "/") -- Convert backslashes to forward slashes for URL

	-- 6. Convert remote URL to a browsable HTTPS URL base
	local base_url
	-- SSH format: git@hostname:user/repo.git
	if remote_url:match("^git@") then
		base_url = remote_url:gsub("^git@", "https://")
		base_url = base_url:gsub(":", "/")
		base_url = base_url:gsub("%.git$", "")
		-- SSH protocol format: ssh://git@hostname/user/repo.git
	elseif remote_url:match("^ssh://") then
		base_url = remote_url:gsub("^ssh://[^@]+@", "https://") -- Remove ssh://user@
		base_url = base_url:gsub("%.git$", "")
		-- HTTPS format: https://hostname/user/repo.git (or https://user@hostname/...)
	elseif remote_url:match("^https://") then
		base_url = remote_url:gsub("^https://[^@]+@", "https://") -- Remove potential user@
		base_url = base_url:gsub("%.git$", "")
	else
		vim.notify("Unsupported remote URL format: " .. remote_url, vim.log.levels.ERROR)
		return
	end

	-- 7. Determine the path segment based on hosting service (heuristic)
	local path_segment = "/blob/" -- GitHub, GitLab, Gitea, Codeberg default
	if base_url:match("bitbucket%.org") then
		path_segment = "/src/"
		-- Azure DevOps needs a different structure entirely, complex to handle generically
		-- Example: https://dev.azure.com/{org}/{project}/_git/{repo}?path=/{filepath}&version=GB{branch}
	elseif base_url:match("dev%.azure%.com") or base_url:match("visualstudio%.com") then
		vim.notify("Azure DevOps has a unique URL structure, attempting standard format may fail.", vim.log.levels.WARN)
		-- If targeting a directory, use '/tree/' instead of '/blob/' or '/src/'
		if vim.fn.isdirectory(target_path) == 1 then
			path_segment = "/tree/"
		end
		-- For Azure, might need special URL construction here if generic fails often
		-- local final_url = base_url .. "?path=" .. vim.uri.encode(relative_path) .. "&version=GB" .. branch
		-- Let's proceed with generic first, see below.
	end

	-- Check if the target is a directory to adjust the path segment if needed
	if vim.fn.isdirectory(target_path) == 1 then
		if path_segment == "/blob/" then
			path_segment = "/tree/"
		end
		if path_segment == "/src/" then
			path_segment = "/browse/"
		end -- Bitbucket uses /browse for dirs
		-- If relative_path is empty, we are Browse the repo root
		if relative_path == "" then
			path_segment = "/tree/" -- Most services use /tree/ for root
			cur_local_branch = cur_local_branch
			relative_path = "" -- No relative path needed
		end
	end

	-- 8. Construct the final URL
	local final_url
	-- Handle Azure DevOps potentially differently if needed (see path_segment logic)
	if
		(base_url:match("dev%.azure%.com") or base_url:match("visualstudio%.com"))
		and vim.fn.isdirectory(target_path) ~= 1
		and relative_path ~= ""
	then
		-- Attempt Azure-specific file URL construction
		-- Note: URI encoding might be needed for branch/path, handled by open command usually
        -- might change remote_branch to local_branch
		final_url = base_url .. "?path=" .. "/" .. relative_path .. "&version=GB" .. cur_remote_branch .. "&line=1" -- Add line=1 maybe
		vim.notify("Using Azure-specific URL format.", vim.log.levels.INFO)
	else
		-- Standard construction for others or Azure directories/root
		final_url = table.concat({ base_url, path_segment, cur_remote_branch, "/", relative_path }, "")
		final_url = final_url:gsub("///", "/"):gsub("//", "/")
		final_url = final_url:gsub(":/", "://")
	end

	-- 9. Determine the OS-specific open command
	local open_cmd
	if vim.fn.has("macunix") == 1 then
		open_cmd = "open"
	elseif vim.fn.has("win32") == 1 then
		open_cmd = "start" -- Use 'start' for URLs/files on Windows
	else -- Assume Linux/other Unix-like
		open_cmd = "xdg-open"
	end

	local open_job_id = vim.fn.jobstart({ open_cmd, final_url }, { detach = true })

	if not open_job_id or open_job_id <= 0 then
		vim.notify("Failed to execute command: " .. open_cmd .. " " .. final_url, vim.log.levels.ERROR)
		-- Fallback attempt with os.execute (might block briefly, less safe quoting)
		-- os.execute(open_cmd .. " " .. vim.fn.shellescape(final_url))
	end
end

return M
