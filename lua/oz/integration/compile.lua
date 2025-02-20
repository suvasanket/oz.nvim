local M = {}
local k = require("oz.mappings.util")
local t = require("oz.term")
local util = require("oz.util")

function M.compile_init(a)
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "compilation", "oz_term" },
		callback = function(event)
			-- compilation to term
			if vim.bo.ft == "compilation" then
				util.Map("n", a.keys.open_in_oz_term, function()
					vim.cmd("CompileInterrupt")
					vim.cmd("close")
					k.cmd_func("Term")
				end, { buffer = event.buf, silent = true, desc = "open in oz_term" })

				-- show keymaps
                util.Map("n", a.keys.show_keybinds, function()
					util.Show_buf_keymaps({ subtext = { "~ generated by oz" } })
				end, { buffer = event.buf, silent = true, desc = "show all keymaps" })

			-- term to compilation
			elseif vim.bo.ft == "oz_term" then
				util.Map("n", "t", function()
					t.close_term()
					k.cmd_func("Compile")
				end, { buffer = event.buf, silent = true, desc = "open in compile_mode" })
			end
		end,
	})
end

return M
