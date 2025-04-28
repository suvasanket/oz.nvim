local M = {}

function M.expand_expressions(str)
	local pattern = "%%[:%w]*"

	local expanded_str = string.gsub(str, pattern, function(exp)
		return vim.fn.expand(exp)
	end)

	return expanded_str
end

function M.parse_args(argstring)
	local args = {}
	local i = 1
	local len = #argstring

	while i <= len do
		-- Skip leading whitespace
		while i <= len and argstring:sub(i, i):match("%s") do
			i = i + 1
		end
		if i > len then
			break
		end

		local start_char = argstring:sub(i, i)

		if start_char == '"' or start_char == "'" then
			-- Handle quoted arguments
			local quote = start_char
			local start = i + 1
			i = i + 1 -- Move past opening quote
			local found_quote = false
			while i <= len do
				if argstring:sub(i, i) == quote then
					found_quote = true
					break
				end
				i = i + 1
			end

			if found_quote then
				table.insert(args, argstring:sub(start, i - 1))
				i = i + 1 -- Move past closing quote
			else
				table.insert(args, argstring:sub(start)) -- Unterminated
			end
		else
			-- Handle non-quoted arguments (potentially with key='value')
			local start = i
			local end_pos = -1 -- Position *after* the argument ends

			local scan_pos = i
			while scan_pos <= len do
				local char = argstring:sub(scan_pos, scan_pos)

				if char:match("%s") then
					end_pos = scan_pos -- Argument ends before the space
					break
				elseif char == "=" then
					if scan_pos + 1 <= len then
						local next_char = argstring:sub(scan_pos + 1, scan_pos + 1)
						if next_char == '"' or next_char == "'" then
							-- Found key='value', find end of quoted value
							local value_quote = next_char
							local quote_end_scan = scan_pos + 2
							while
								quote_end_scan <= len
								and argstring:sub(quote_end_scan, quote_end_scan) ~= value_quote
							do
								quote_end_scan = quote_end_scan + 1
							end

							if quote_end_scan <= len then
								end_pos = quote_end_scan + 1 -- Argument ends *after* the closing quote
							else
								end_pos = len + 1 -- Unterminated value quote, arg ends at string end
							end
							break -- Definitively found end for this key='value' argument
						else
							scan_pos = scan_pos + 1 -- '=' not followed by quote
						end
					else
						scan_pos = scan_pos + 1 -- '=' is last char
					end
				else
					scan_pos = scan_pos + 1 -- Normal character
				end
			end

			if end_pos == -1 then -- Loop finished without break (reached end of string)
				end_pos = len + 1
			end

			table.insert(args, argstring:sub(start, end_pos - 1))
			i = end_pos -- Update main loop iterator for next argument
		end
	end

	return args
end

return M
