--- @class oz.util.ui
local M = {}

--- Display a message in the command line using `nvim_echo`.
--- @param str string The message to display.
--- @param hl? string Optional highlight group (defaults to "MoreMsg").
function M.echoprint(str, hl)
	if not hl then
		hl = "MoreMsg"
	end
	vim.api.nvim_echo({ { str, hl } }, true, {})
end

--- Display an inactive (dimmed) message in the echo area.
--- @param str string The message to display.
function M.inactive_echo(str)
	if not str or str == "" or vim.fn.strdisplaywidth(str) >= vim.v.echospace then
		return
	end
	require("oz.util.hl").setup_hls({ "ozInactivePrompt" })
	vim.api.nvim_echo({ { "" } }, false, {})
	vim.api.nvim_echo({ { str, "ozInactivePrompt" } }, false, {})
end

--- Get input from the user using `vim.fn.input`.
--- @param prompt string The prompt to display.
--- @param text? string Optional default text.
--- @param complete? string Optional completion type.
--- @return string|nil The user input, or nil if cancelled.
function M.UserInput(prompt, text, complete)
	local ok, input
	if complete then
		ok, input = pcall(vim.fn.input, prompt, text or "", complete)
	else
		ok, input = pcall(vim.fn.input, prompt, text or "")
	end
	if ok then
		return input
	end
end

--- Get input from the user with a dimmed prompt highlight.
--- @param str string The prompt to display.
--- @param def? string Optional default text.
--- @param complete? string Optional completion type.
--- @return string|nil The user input, or nil if cancelled.
function M.inactive_input(str, def, complete)
	require("oz.util.hl").setup_hls({ "ozInactivePrompt" })
	vim.cmd("echohl ozInactivePrompt")
	local input = M.UserInput(str, def, complete)
	vim.cmd("echohl None")
	return input
end

--- Display a notification.
--- @param content string The notification content.
--- @param level? "error"|"warn"|"info"|"debug"|"trace" Optional notification level.
--- @param title? string Optional title.
--- @param once? boolean Whether to use `notify_once`.
function M.Notify(content, level, title, once)
	title = title or "Info"

	local level_map = {
		error = vim.log.levels.ERROR,
		warn = vim.log.levels.WARN,
		info = vim.log.levels.INFO,
		debug = vim.log.levels.DEBUG,
		trace = vim.log.levels.TRACE,
	}
	local log_level = level_map[level] or vim.log.levels.INFO
	if once then
		vim.notify_once(content, log_level, { title = title })
	else
		vim.notify(content, log_level, { title = title })
	end
end

--- Display a confirmation prompt using `vim.fn.confirm`.
--- @param str string The message.
--- @param choice? string Choice buttons (e.g., "&Yes\n&No").
--- @param default? integer Default button index.
--- @param hl? string Optional highlight for the message.
--- @return integer|nil The index of the chosen button, or nil if cancelled.
function M.prompt(str, choice, default, hl)
	local ok, res = pcall(vim.fn.confirm, str, choice, default, hl)
	if ok then
		return res
	end
end

--- Open a URL in the system's default browser.
--- @param url string The URL to open.
function M.open_url(url)
	if not url or not (url:match("^https?://") or url:match("^file://")) then
		M.Notify("Not a valid url.", "warn", "oz_doctor")
		return
	end
	local open_cmd
	if vim.fn.has("macunix") == 1 then
		open_cmd = "open"
	elseif vim.fn.has("win32") == 1 then
		open_cmd = "start"
	else
		open_cmd = "xdg-open"
	end

	local open_job_id = vim.fn.jobstart({ open_cmd, url }, { detach = true })
	if not open_job_id or open_job_id <= 0 then
		M.Notify("Opening url unsuccessful!", "error", "oz_doctor")
	end
end

--- Create temporary autocommands for command-line completion behavior.
function M.transient_cmd_complete()
	local group = vim.api.nvim_create_augroup("CmdwinEventsTransient", { clear = true })
	local d_wildmode = vim.o.wildmode
	vim.api.nvim_create_autocmd("CmdlineChanged", {
		group = group,
		callback = function()
			vim.o.wildmode = "noselect:lastused,full"
			pcall(vim.fn.wildtrigger)
		end,
	})
	vim.api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		once = true,
		callback = function()
			vim.o.wildmode = d_wildmode
			pcall(vim.api.nvim_del_augroup_by_name, "CmdwinEventsTransient")
		end,
	})
end

--- Populate the command-line with a string and position the cursor at a marker (`|`).
--- @param str string The command string.
function M.set_cmdline(str)
	local cmdline = str:gsub("%%|", "")
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(":<C-U>" .. cmdline, true, false, true), "n", false)
	local cursor_pos = str:find("%%|")
	if cursor_pos then
		vim.api.nvim_input(string.rep("<Left>", #str - cursor_pos))
	end
	M.transient_cmd_complete()
end

return M
