local M = {}

M.instances = {}

local next_id = 1

---@param id number|string|nil
---@return number|nil
function M.get_target_id(id)
	local target_id = tonumber(id)

	if target_id then
		return target_id
	end

	if vim.bo.ft == "oz_term" then
		return vim.b.oz_term_id
	end

	local max_id = -1

	for tid, _ in pairs(M.instances) do
		if tid > max_id then
			max_id = tid
		end
	end

	return max_id ~= -1 and max_id or nil
end

function M.setup_buf_cleanup(id, buf)
	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = buf,
		callback = function()
			if M.instances[id] and M.instances[id].buf == buf then
				if M.instances[id].job_id then
					pcall(vim.fn.jobstop, M.instances[id].job_id)
				end
				M.instances[id] = nil
			end
		end,
	})
end

function M.register_instance(id, data)
	M.instances[id] = data
	vim.b[data.buf].oz_term_id = id
	M.setup_buf_cleanup(id, data.buf)
end

function M.get_active_job()
	for id, inst in pairs(M.instances) do
		if inst.job_active then
			return id
		end
	end
	return nil
end

function M.get_last_job()
	local last_id = -1

	for id in pairs(M.instances) do
		if id > last_id then
			last_id = id
		end
	end

	return last_id ~= -1 and last_id or nil
end

function M.toggle(id)
	local target_id = M.get_target_id(id)

	local inst = M.instances[target_id]

	if not inst then
		return
	end

	if inst.win and vim.api.nvim_win_is_valid(inst.win) then
		vim.api.nvim_win_close(inst.win, true)
		inst.win = nil
	else
		vim.cmd("botright split")
		inst.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(inst.win, inst.buf)
	end
end

function M.close(id)
	local target_id = M.get_target_id(id)

	if not target_id then
		return
	end

	local inst = M.instances[target_id]

	if not inst then
		return
	end

	if inst.job_id then
		pcall(vim.fn.jobstop, inst.job_id)
	end

	if inst.buf and vim.api.nvim_buf_is_valid(inst.buf) then
		local wins = vim.fn.win_findbuf(inst.buf)
		for _, win in ipairs(wins) do
			if vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end
		vim.api.nvim_buf_delete(inst.buf, { force = true })
	end

	M.instances[target_id] = nil
end

function M.next_id()
	local id = next_id
	next_id = next_id + 1
	return id
end

--- run with arg util
---@param cmd string
---@param opts {cwd: string, stdin: string}
function M.run_with_arg(cmd, opts)
	if cmd and cmd ~= "" then
		require("oz.term.executor").run(cmd, opts)
	end
end

return M
