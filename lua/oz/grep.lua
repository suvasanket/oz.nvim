local M = {}

function M.cmd_contains_grep(cmd)
	local has_tool = cmd:match("grep") or cmd:match("rg")
	if not has_tool then
		return false -- No grep or rg found
	end
	if cmd:match("rg") then
		local grepprg = vim.o.grepprg
		if not grepprg:match("rg") then
			print("Warning: Vim's grepprg is not set to use ripgrep (rg). You should configure it.")
		end
	end
	local has_pattern = cmd:match("'(.-)'") or cmd:match('"(.-)"') or cmd:match("%s+(%S+)")
	if not has_pattern then
		return false
	end
	return true
end

-- if cmd contains grep use vim's grep then
function M.run_vim_grep(cmd, dir)
	local rest = string.match(cmd, "'(.-)'") or string.match(cmd, '"(.-)"')
	dir = dir or "."

	if cmd:match("rg") then
		vim.o.grepprg = "rg --vimgrep --smart-case --follow"
		if rest then
			cmd = "silent! grep '" .. rest .. "' " .. dir
			vim.cmd(cmd .. " | copen")
		end
	else
		vim.o.grepprg = "grep"
		if rest then
			vim.cmd([[silent! grep ']] .. cmd .. "' " .. dir)
			vim.cmd("copen")
		end
	end
end
return M
