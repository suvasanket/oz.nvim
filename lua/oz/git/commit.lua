local M = {}
local util = require("oz.util")

function M.get_commit_filepath()
	local git_dir_command = "git rev-parse --git-dir 2>/dev/null"
	local git_dir = vim.fn.system(git_dir_command):gsub("%s+$", "")

	-- If git directory not found, silently return
	if vim.v.shell_error ~= 0 then
		return nil
	end

	return git_dir .. "/COMMIT_EDITMSG"
end

-- Function that processes the filtered lines
local function process_commit_lines(lines)
	local commit_msg_file = M.get_commit_filepath()

	if commit_msg_file then
		local file = io.open(commit_msg_file, "w")
		if file then
			for _, line in ipairs(lines) do
				file:write(line .. "\n")
			end
			file:close()
		end
	end
end

function M.create_temp_commit_buffer(initial_content, callback)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.cmd("botright 14 split")

	vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "ft", "gitcommit")
	vim.api.nvim_buf_set_name(buf, "COMMIT_EDITMSG")

	if initial_content then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_content)
	end

	local augroup = vim.api.nvim_create_augroup("TempBufferSave", { clear = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		buffer = buf,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			local filtered_lines = {}
			for _, line in ipairs(lines) do
				if not line:match("^%s*#") then
					table.insert(filtered_lines, line)
				end
			end

			-- Process the filtered lines
			process_commit_lines(filtered_lines)

			vim.api.nvim_buf_set_option(buf, "modified", false)
			vim.api.nvim_echo({ { "Commit message processed", "Normal" } }, true, {})
			vim.cmd("bd")

			util.ShellCmd({ "git", "commit", "-F", M.get_commit_filepath() }, function()
				if callback then
					callback()
				else
					require("oz.git.wizard").commit_wizard()
				end
			end, function()
				util.Notify("Error occured while commiting.", "error", "oz_git")
			end)
			return true
		end,
	})

	vim.api.nvim_set_current_buf(buf)

	return buf
end

local function get_initial_content()
	local status_tbl = {}
	local status_str = util.ShellOutput("git status")
	for substr in status_str:gmatch("([^\n]*)\n?") do
		if substr ~= "" and not substr:match('%(use "git .-.%)') then
			table.insert(status_tbl, substr)
		end
	end
	for i, line in ipairs(status_tbl) do
		status_tbl[i] = "# " .. line
	end
	local whole_tbl = {
		"",
		"# Whenever you write to this buffer, it will automatically get closed",
		"# and your commit will be done. Lines starting with '#' will be ignored,",
		"# and an empty message aborts the commit.",
		"#",
		unpack(status_tbl),
	}

	return whole_tbl
end

function M.git_commit(callback)
	local changed = util.ShellOutputList("git diff --name-only --cached")
	if #changed > 0 then
		local initial_content = get_initial_content()
		if callback then
			M.create_temp_commit_buffer(initial_content, callback)
		else
			M.create_temp_commit_buffer(initial_content)
		end
	else
		util.Notify("Nothing to commit try adding something first.", "error", "oz_git")
	end
end

return M
