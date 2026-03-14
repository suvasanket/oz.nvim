local M = {}
local util = require("oz.util")
local log_util = require("oz.git.log.util")

local run_n_refresh = log_util.run_n_refresh
local cmd_upon_current_commit = log_util.cmd_upon_current_commit

-- Helper to construct args
local function get_args(flags)
	if flags and #flags > 0 then
		return " " .. table.concat(flags, " ")
	end
	return ""
end

function M.squash(flags)
	local args = get_args(flags)
	cmd_upon_current_commit(function(hash)
		run_n_refresh("Git commit" .. args .. " --squash " .. hash)
	end)
end

function M.fixup(flags)
	local args = get_args(flags)
	cmd_upon_current_commit(function(hash)
		run_n_refresh("Git commit" .. args .. " --fixup " .. hash)
	end)
end

function M.fixup_instant()
	cmd_upon_current_commit(function(hash)
		local git = require("oz.git")
		local ok = util.run_command({ "git", "rev-parse", "--verify", hash .. "^" })
		local base = ok and hash .. "^" or "--root"

		git.on_job_exit("fixup_instant", {
			once = true,
			callback = function(res)
				if res.exit_code == 0 then
					vim.schedule(function()
						run_n_refresh(string.format("Git rebase -i --autosquash %s", base))
					end)
				end
			end,
		})
		run_n_refresh(string.format("Git commit --fixup %s", hash))
	end)
end

function M.amend_instant()
	run_n_refresh("Git commit --amend --no-edit")
end

function M.commit()
    cmd_upon_current_commit(function(hash)
        util.set_cmdline("Git commit| " .. hash)
    end)
end

function M.extend()
    cmd_upon_current_commit(function(hash)
        run_n_refresh(("Git commit -C %s -q"):format(hash))
    end)
end

function M.amend()
    cmd_upon_current_commit(function(hash)
        run_n_refresh(("Git commit -c %s -q"):format(hash))
    end)
end

function M.reword()
	cmd_upon_current_commit(function(hash)
		local is_head = util.shellout_str("git rev-parse HEAD"):find(hash) ~= nil
		if is_head then
			run_n_refresh("Git commit --amend")
		else
			local ok = util.run_command({ "git", "rev-parse", "--verify", hash .. "^" })
			local base = ok and hash .. "^" or "--root"
			util.Notify("Rewording non-HEAD commit requires interactive rebase.", "info", "oz_git")
			run_n_refresh(string.format("Git rebase -i %s", base))
		end
	end)
end

function M.drop()
	cmd_upon_current_commit(function(hash)
		local ok = util.run_command({ "git", "rev-parse", "--verify", hash .. "^" })
		if not ok then
			util.Notify("Cannot drop root commit via rebase --onto.", "error", "oz_git")
			return
		end
		run_n_refresh(string.format("Git rebase --onto %s^ %s", hash, hash))
	end)
end

function M.setup_keymaps(buf, key_grp)
	local options = {
		{
			title = "Switches",
			items = {
				{ key = "-e", name = "--edit", type = "switch", desc = "Edit" },
				{ key = "-n", name = "--no-verify", type = "switch", desc = "No verify" },
			},
		},
		{
			title = "Commit",
			items = {
				{ key = "s", cb = M.squash, desc = "Create commit with commit under cursor(--squash)" },
				{ key = "f", cb = M.fixup, desc = "Create commit with commit under cursor(--fixup)" },
				{ key = "F", cb = M.fixup_instant, desc = "Fixup & Instant Autosquash" },
				{ key = "c", cb = M.commit, desc = "Populate cmdline with Git commit followed by current hash" },
				{ key = "e", cb = M.extend, desc = "Create commit & reuse message from commit under cursor" },
				{ key = "a", cb = M.amend, desc = "Create commit & edit message from commit under cursor" },
				{ key = "A", cb = M.amend_instant, desc = "Instant Amend HEAD (--no-edit)" },
				{ key = "w", cb = M.reword, desc = "Reword commit under cursor" },
				{ key = "d", cb = M.drop, desc = "Drop commit under cursor" },
			},
		},
		{
			title = "Actions",
			items = {
				{
					key = " ",
					cb = function(f)
						local flags = f and table.concat(f, " ") or ""
						util.set_cmdline("Git commit " .. flags .. " ")
					end,
					desc = "Commit (edit cmd)",
				},
			},
		},
	}

	vim.keymap.set("n", "c", function()
		util.show_menu("Commit Actions", options)
	end, { buffer = buf, desc = "Commit Actions", nowait = true, silent = true })
end

return M
