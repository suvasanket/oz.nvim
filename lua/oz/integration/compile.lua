local M = {}
local k = require("oz.mappings")

function M.compile_init()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "compilation",
		callback = function(event)
			vim.keymap.set("n", "t", function()
				vim.cmd("CompileInterrupt")
				vim.cmd("close")
				k.cmd_func("Term")
			end, { buffer = event.buf, silent = true })
		end,
	})
end

return M
