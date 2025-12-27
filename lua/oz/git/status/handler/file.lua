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
	local entries = s_util.get_file_under_cursor()
	local section = s_util.get_section_under_cursor()

	if #entries > 0 then
		s_util.run_n_refresh("Git add " .. quote_and_join(entries))
	elseif section == "unstaged" then
		s_util.run_n_refresh("Git add -u")
	elseif section == "untracked" then
		util.set_cmdline(":Git add .")
	end
end

function M.unstage()
	local entries = s_util.get_file_under_cursor()
	local section = s_util.get_section_under_cursor()

	if #entries > 0 then
		s_util.run_n_refresh(string.format("Git restore --staged %s -q", quote_and_join(entries)))
	elseif section == "staged" then
		s_util.run_n_refresh("Git reset -q")
	end
end

function M.discard()
	local entries = s_util.get_file_under_cursor()
	if #entries > 0 then
		local confirm_ans = util.prompt("Discard all the changes?", "&Yes\n&No", 2)
		if confirm_ans == 1 then
			s_util.run_n_refresh(string.format("Git restore %s -q", quote_and_join(entries)))
		end
	end
end

function M.untrack()
	local entries = s_util.get_file_under_cursor()
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
	util.Map({ "n", "x" }, "s", M.stage, { buffer = buf, desc = "Stage entry under cursor or selected entries." })
	-- unstage
	util.Map({ "n", "x" }, "u", M.unstage, { buffer = buf, desc = "Unstage entry under cursor or selected entries." })
	-- discard
	util.Map({ "n", "x" }, "X", M.discard, { buffer = buf, desc = "Discard entry under cursor or selected entries." })
	util.Map({ "n", "x" }, "K", M.untrack, { buffer = buf, desc = "Untrack file or selected files." })
	util.Map("n", "R", M.rename, { buffer = buf, desc = "Rename the file under cursor." })

	key_grp["File actions"] = { "s", "u", "K", "X", "R" }
end

return M
