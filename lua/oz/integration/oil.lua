local M = {}
local term = require("oz.term")
local util = require("oz.util")
local p = require("oz.persistcmd")

function M.oil_init(term_key, compile_key)
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "oil",
		callback = function(event)
			if term_key then
				vim.keymap.set("n", term_key, function()
					local oil_cwd = require("oil").get_current_dir()
					local cmd = p.getoilcmd(oil_cwd) or ""
					local input = util.UserInput(":Term ", cmd)
					if input then
						if cmd ~= input then
							p.setoilcmd(oil_cwd, input)
						end
						term.run_in_term(input, oil_cwd)
					end
				end, { buffer = event.buf, silent = true })
			end

			if compile_key then
				vim.keymap.set("n", compile_key, function()
					local oil_cwd = require("oil").get_current_dir()
                    vim.g.compilation_directory = oil_cwd
					local cmd = p.getoilcmd(oil_cwd) or ""
					local input = util.UserInput(":Compile ", cmd)
					if input then
						if cmd ~= input then
							p.setoilcmd(oil_cwd, input)
						end
						vim.cmd("Compile " .. input)
					end
				end, { buffer = event.buf, silent = true })
			end
		end,
	})
end
return M
