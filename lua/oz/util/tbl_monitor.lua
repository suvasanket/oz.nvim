local M = {}

local monitoring_timers = {}

M.start_monitoring = function(tbl, options)
	options = options or {}
	for _, m in ipairs(monitoring_timers) do
		if m.tbl == tbl and m.buf == options.buf then
			if #tbl > 0 and options.on_active then
				options.on_active(tbl)
			elseif #tbl == 0 and options.on_empty then
				options.on_empty()
			end
			return false
		end
	end

	local timer = vim.loop.new_timer()
	local monitor = {
		tbl = tbl,
		buf = options.buf,
		timer = timer,
		options = options,
	}

	if #tbl > 0 and options.on_active then
		options.on_active(tbl)
	elseif #tbl == 0 and options.on_empty then
		options.on_empty()
	end

	timer:start(
		options.interval or 2000,
		options.interval or 2000,
		vim.schedule_wrap(function()
			if options.buf and vim.api.nvim_get_current_buf() ~= options.buf then
				return
			end
			if #tbl > 0 then
				if options.on_active then
					options.on_active(tbl)
				end
			else
				if options.on_empty then
					options.on_empty()
				end
				M.stop_monitoring(tbl) -- Auto-stop when empty
			end
		end)
	)

	table.insert(monitoring_timers, monitor)
	return true
end

M.stop_monitoring = function(tbl)
	local found = false
	for i = #monitoring_timers, 1, -1 do
		if monitoring_timers[i].tbl == tbl then
			monitoring_timers[i].timer:stop()
			monitoring_timers[i].timer:close()
			table.remove(monitoring_timers, i)
			found = true
		end
	end
	return found
end

M.is_monitoring = function(tbl)
	for _, m in ipairs(monitoring_timers) do
		if m.tbl == tbl then
			return true
		end
	end
	return false
end

M.stop_all_monitoring = function()
	for _, m in ipairs(monitoring_timers) do
		m.timer:stop()
		m.timer:close()
	end
	monitoring_timers = {}
end

return M
