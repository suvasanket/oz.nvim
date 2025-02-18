local M = {}
local k = require("oz.mappings")
local t = require("oz.term")

function M.compile_init()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "compilation", "oz_term" },
		callback = function(event)
            -- compilation to term
			if vim.bo.ft == "compilation" then
				vim.keymap.set("n", "t", function()
					vim.cmd("CompileInterrupt")
					vim.cmd("close")
					k.cmd_func("Term")
				end, { buffer = event.buf, silent = true })
            -- term to compilation
			elseif vim.bo.ft == "oz_term" then
                vim.keymap.set("n", "t", function()
                    t.close_term()
					k.cmd_func("Compile")
                end, { buffer = event.buf, silent = true })
			end
		end,
	})
end

return M
