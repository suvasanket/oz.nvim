local M = {}
local util = require("oz.util")
local p = require("oz.persistcmd")
local d = require("oz.mappings.comp_detect")

TerminalCommandType = nil

-- TermBang mapping
function M.termbangkey_init(key)
	vim.keymap.set("n", key, function()
		local current_file = vim.fn.expand("%")
		local cmd = p.getTermBcmd(current_file) or ""

		local input = util.UserInput(":Term! ", cmd)
		if input then
			vim.cmd("Term! " .. input)

			if cmd ~= input then
				p.setTermBcmd(current_file, input)
			end
			TerminalCommandType = "Term!"
		end
	end, { desc = "oz Term!", silent = false })
end

-- run command for both Compile-Term
function M.cmd_func(type)
	local current_file = vim.fn.expand("%")
	local ft = vim.bo.filetype
	local shebang = d.detect_shebang()
	local project_path = util.GetProjectRoot() -- may return nil
	-- p: 1
	if not shebang then
		-- p: 2 , 3
		local cmd
		if project_path then
			cmd = p.getpersistCMD(project_path, current_file, ft) or p.getftCMD(current_file, ft)
		else
			cmd = p.getftCMD(current_file, ft)
		end
		if not cmd then
			-- p: 4
			cmd = d.predict_compiler(current_file, ft)
		end
		local input = util.UserInput(":" .. type .. " ", cmd)
		if input then
			vim.cmd(type .. " " .. input)
			-- modify for set
			input = input:gsub('"', '\\"')

			if cmd ~= input and project_path then
				p.setpersistCMD(project_path, current_file, ft, input)
			end
			if input:find(current_file) then
				if project_path then
					p.setpersistCMD(project_path, current_file, ft, input)
				else
					p.setftCMD(current_file, ft, input)
				end
			end
		end
	else
		vim.api.nvim_feedkeys(":" .. type .. " " .. shebang .. " " .. current_file, "n", false)
	end
end

-- Term mapping
function M.termkey_init(key)
	vim.keymap.set("n", key, function()
		M.cmd_func("Term")
		TerminalCommandType = "Term"
	end, { desc = "oz term", silent = false })
end

-- Compile mapping
function M.compilekey_init(key)
	vim.keymap.set("n", key, function()
		M.cmd_func("Compile")
		TerminalCommandType = "Recompile"
	end, { desc = "Compile with oz", silent = false })
end

-- Rerunner
function M.rerunner_init(key)
	vim.keymap.set("n", key, function()
		if TerminalCommandType then
			vim.cmd([[w]])
			vim.cmd(TerminalCommandType)
			if TerminalCommandType == "Term" then
				vim.cmd.wincmd([[p]])
			end
		end
	end)
end

return M
