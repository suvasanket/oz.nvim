local M = {}

--- Parse a command string into a table of arguments, handling quotes and key=value pairs.
--- @param argstring string The string to parse.
--- @return string[] A table of parsed arguments.
function M.parse_args(argstring)
	argstring = vim.fn.expandcmd(argstring)

	local args = {}
	local len = #argstring
	local i = 1

	while i <= len do
		local char = argstring:sub(i, i)

		-- Skip whitespace
		if char:match("%s") then
			i = i + 1
		else
			local arg_start = i
			local arg_end

			-- Quoted argument
			if char == '"' or char == "'" then
				local quote = char
				i = i + 1
				arg_start = i

				-- Find closing quote
				arg_end = argstring:find(quote, i, true)
				if arg_end then
					args[#args + 1] = argstring:sub(arg_start, arg_end - 1)
					i = arg_end + 1
				else
					-- Unterminated quote
					args[#args + 1] = argstring:sub(arg_start)
					break
				end
			else
				-- Non-quoted argument
				local eq_pos = argstring:find("=", i, true)

				-- Check for key='value' or key="value"
				if eq_pos and eq_pos < len then
					local next_char = argstring:sub(eq_pos + 1, eq_pos + 1)
					if next_char == '"' or next_char == "'" then
						-- Find end of quoted value
						local close_quote = argstring:find(next_char, eq_pos + 2, true)
						if close_quote then
							args[#args + 1] = argstring:sub(arg_start, close_quote)
							i = close_quote + 1
						else
							-- Unterminated
							args[#args + 1] = argstring:sub(arg_start)
							break
						end
					else
						-- key=unquoted or just regular text with =
						arg_end = argstring:find("%s", i)
						if arg_end then
							args[#args + 1] = argstring:sub(arg_start, arg_end - 1)
							i = arg_end + 1
						else
							args[#args + 1] = argstring:sub(arg_start)
							break
						end
					end
				else
					-- Regular unquoted argument
					arg_end = argstring:find("%s", i)
					if arg_end then
						args[#args + 1] = argstring:sub(arg_start, arg_end - 1)
						i = arg_end + 1
					else
						args[#args + 1] = argstring:sub(arg_start)
						break
					end
				end
			end
		end
	end

	return args
end

return M
