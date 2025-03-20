local M = {}

local function ft_options()
	vim.cmd([[setlocal listchars= nonumber norelativenumber]])
	vim.bo.modifiable = false
	vim.bo.bufhidden = "wipe"
	vim.bo.buftype = "nofile"
	vim.bo.swapfile = false
end

local function ft_mappings(buf)
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "close oz_git" })
	vim.keymap.set("n", "<C-g>", function()
		local cfile = vim.fn.expand("<cfile>")
		vim.api.nvim_feedkeys(":" .. cfile, "n", false)
		vim.schedule(function()
            vim.api.nvim_input("<Home>Git <left> ")
		end)
	end, { buffer = buf, silent = true })
end

local function ft_hl()
	vim.cmd("syntax clear")

	-- Syntax matches
	vim.cmd("syntax match ozGitAuthor '\\<Author\\>' containedin=ALL")
	vim.cmd("syntax match ozGitDate '\\<Date\\>' containedin=ALL")
	vim.cmd("syntax match ozGitCommitHash '\\<[0-9a-f]\\{7,40}\\>' containedin=ALL")
	vim.cmd([[syntax match ozGitBranchName /\(On branch \)\@<=\S\+/ contained]])
	vim.cmd([[syntax match ozGitSection /^Untracked files:$/]])
	vim.cmd([[syntax match ozGitSection /^Changes not staged for commit:$/]])
	vim.cmd([[syntax match ozGitModified /^\s\+modified:\s\+.*$/]])
	vim.cmd([[syntax match ozGitUntracked /^\s\+\%(\%(modified:\)\@!.\)*$/]])

	vim.cmd([[syntax match ozGitDiffMeta /^@@ .\+@@/]])
	vim.cmd([[syntax match ozGitDiffAdded /^+.\+$/]])
	vim.cmd([[syntax match ozGitDiffRemoved /^-.\+$/]])
	vim.cmd([[syntax match ozGitDiffHeader /^diff --git .\+$/]])
	vim.cmd([[syntax match ozGitDiffFile /^\(---\|+++\) .\+$/]])

	-- Highlight groups
	vim.cmd("highlight default link ozGitBranchName @function")
	vim.api.nvim_set_hl(0, "ozGitUntracked", { fg = "#757575" })
	vim.cmd("highlight default link ozGitModified @diff.delta")
	vim.cmd("highlight default link ozGitSection @function")

	vim.cmd("highlight default link ozGitDiffAdded @diff.plus")
	vim.cmd("highlight default link ozGitDiffRemoved @diff.minus")
	vim.cmd("highlight default link ozGitDiffMeta @diff.delta")
	vim.cmd("highlight default link ozGitDiffFile @function")
	vim.cmd("highlight default link ozGitDiffHeader @comment.todo")

	vim.cmd("highlight default link ozGitAuthor @function")
	vim.cmd("highlight default link ozGitDate @function")
	vim.cmd("highlight default link ozGitCommitHash @attribute")
end

-- In your plugin's Lua file
function M.oz_git_hl()
	local oz_git_syntax = vim.api.nvim_create_augroup("OzGitSyntax", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "oz_git",
		group = oz_git_syntax,
		callback = function(event)
			ft_options()
			ft_hl()
			ft_mappings(event.buf)
		end,
	})
end

return M
