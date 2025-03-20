local M = {}

-- In your plugin's Lua file
function M.oz_git_hl()
	local oz_git_syntax = vim.api.nvim_create_augroup("OzGitSyntax", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "oz_git",
		group = oz_git_syntax,
		callback = function()
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
			vim.api.nvim_set_hl(0, "ozGitUntracked", { fg = "#606060" })
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
		end,
	})
end

return M
