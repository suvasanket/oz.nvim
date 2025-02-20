local M = {}
local util = require("oz.util")
local p = require("oz.persistcmd")
local u = require("oz.mappings.util")

M.RunnerCommandType = nil

-- TermBang mapping
function M.Termbang()
    local current_file = vim.fn.expand("%")
    local cmd = p.getTermBcmd(current_file) or ""

    local input = util.UserInput(":Term! ", cmd)
    if input then
        vim.cmd("Term! " .. input)

        if cmd ~= input then
            p.setTermBcmd(current_file, input)
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
    u.cmd_func("Term")
    M.RunnerCommandType = "Term"
end
function M.termkey_init(key)
	util.Map("n", key, function()
        M.Term()
	end, { desc = "oz term", silent = false })
end

-- Compile mapping
function M.Compile_mode()
    u.cmd_func("Compile")
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
        vim.cmd([[w]])
        vim.cmd(M.RunnerCommandType)
        if M.RunnerCommandType == "Term" then
            vim.cmd.wincmd([[p]])
        end
    end
end
function M.rerunner_init(key)
	util.Map("n", key, function()
        M.Rerun()
	end)
end

return M
