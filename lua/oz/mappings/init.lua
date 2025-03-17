local M = {}
local util = require("oz.util")
local p = require("oz.caching")
local u = require("oz.mappings.util")
local t = require("oz.term")
local term_bang_json = "termbang"

M.RunnerCommandType = nil

-- TermBang mapping
function M.Termbang()
	-- check if in oz_term
	if vim.bo.ft == "oz_term" then
		vim.cmd("wincmd p")
	end
	local current_file = vim.fn.expand("%")
	local cmd = p.get_data(current_file, term_bang_json) or ""

	local input = util.UserInput(":Term! ", cmd)
	if input then
		if input:match("^@") then
			input = input:gsub("@", "")
			t.run_in_termbang(input, util.GetProjectRoot())
		else
			t.run_in_termbang(input)
		end

		if cmd ~= input then
			p.set_data(current_file, input, term_bang_json)
		end
		M.RunnerCommandType = "Term!"
	end
end
function M.termbangkey_init(key)
	util.Map("n", key, function()
		M.Termbang()
	end, { desc = "[oz_term]Term!", silent = false })
end

-- Term mapping
function M.Term()
	-- check if in oz_term
	if vim.bo.ft == "oz_term" then
		vim.cmd("wincmd p")
	end
	u.cmd_func("Term", function(input)
		if input:match("^@") then
			input = input:gsub("@", "")
			t.run_in_term(input, util.GetProjectRoot())
		else
			t.run_in_term(input)
		end
	end)
	M.RunnerCommandType = "Term"
end
function M.termkey_init(key)
	util.Map("n", key, function()
		M.Term()
	end, { desc = "[oz_term]Term", silent = false })
end

-- Rerunner
function M.Rerun()
	if M.RunnerCommandType then
		vim.cmd(M.RunnerCommandType)
	end
end
function M.rerunner_init(key)
	util.Map("n", key, function()
		M.Rerun()
	end, { desc = "[oz_term]Rerun" })
end

return M
