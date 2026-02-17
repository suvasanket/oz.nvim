local M = {}

--- Run a shell command using `jobstart`.
--- @param cmd string|string[] The command to execute.
--- @param on_success? function Callback on success (exit code 0).
--- @param on_error? function Callback on error (non-zero exit code).
function M.ShellCmd(cmd, on_success, on_error)
	local ok = pcall(vim.fn.jobstart, cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_exit = function(_, code)
			if code == 0 then
				if on_success then
					on_success()
				end
			else
				if on_error then
					on_error()
				end
			end
		end,
	})
	if not ok then
		require("oz.util.ui").Notify("oz: something went wrong while executing cmd with jobstart().", "error", "Error")
		return
	end
end

--- Check if a user command exists.
--- @param name string The command name.
--- @return boolean True if the command exists.
function M.usercmd_exist(name)
	local commands = vim.api.nvim_get_commands({})
	return commands[name] ~= nil
end

--- Clear the quickfix list if it has a specific title.
--- @param title string The title to match.
function M.clear_qflist(title)
	local qf_list = vim.fn.getqflist({ title = 1 })
	if qf_list.title == title then
		vim.fn.setqflist({}, "r")
		vim.cmd("cclose")
	end
end

--- Extract flags starting with `-` from a command string.
--- @param cmd_str string The command string.
--- @return string[] Table of extracted flags.
function M.extract_flags(cmd_str)
	local flags = {}

	if not cmd_str or cmd_str == "" then
		return flags
	end

	for part in string.gmatch(cmd_str, "[^%s]+") do
		if string.sub(part, 1, 1) == "-" then
			table.insert(flags, part)
		end
	end

	return flags
end

--- Generate a unique random ID.
--- @return string A 5-character unique ID.
function M.generate_unique_id()
	math.randomseed(os.time())
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local len = 5
	local str = ""
	for i = 1, len do
		local r = math.random(#chars)
		str = str .. chars:sub(r, r)
	end
	return str
end

function M.Map(mode, lhs, rhs, opts)
    if type(lhs) ~= "table" then
        return
    end

    opts = vim.tbl_extend("force", { silent = true }, opts or {})

    for _, k in ipairs(lhs) do
        vim.keymap.set(mode, k, rhs, opts)
    end
end

--- Exit visual mode.
function M.exit_visual()
    if vim.api.nvim_get_mode().mode:match("[vV]") then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    end
end

return M
