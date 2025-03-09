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
	end, { desc = "oz Term!", silent = false })
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
	end, { desc = "oz term", silent = false })
end

-- Compile mapping
function M.Compile_mode()
    -- check if in oz_term
    if vim.bo.ft == "oz_term" then
        vim.cmd("wincmd p")
    end
	u.cmd_func("Compile", function(input)
		if input:match("^@") then
			util.Notify("compile-mode doesn't support project-root cmd execution.", "warn", "oz")
		end
		input = input:gsub("@", "")
		vim.cmd("Compile " .. input)
	end)
	M.RunnerCommandType = "Recompile"
end
function M.compilekey_init(key)
	util.Map("n", key, function()
		M.Compile_mode()
	end, { desc = "Compile with oz", silent = false })
end

-- Rerunner
function M.Rerun()
	if M.RunnerCommandType then
		local pos = vim.api.nvim_win_get_cursor(0)
		vim.cmd(M.RunnerCommandType)
		vim.fn.timer_start(10, function()
			if M.RunnerCommandType == "Term" then
				vim.cmd("wincmd p")
				pcall(vim.api.nvim_win_set_cursor, 0, pos)
			end
		end)
	end
end
function M.rerunner_init(key)
	util.Map("n", key, function()
		M.Rerun()
	end)
end

return M
