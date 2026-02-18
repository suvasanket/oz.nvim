--- @class oz.util.tbl
local M = {}

--- Add item to table only if it doesn't already exist.
--- @param tbl any[] The target table.
--- @param item any The item to insert.
--- @param pos? integer Optional position to insert at.
--- @return any[] The updated table.
function M.tbl_insert(tbl, item, pos)
	if not vim.tbl_contains(tbl, item) then
		if pos then
			table.insert(tbl, pos, item)
		else
			table.insert(tbl, item)
		end
	end
	return tbl
end

--- Check if a trimmed version of `str` exists as a substring in any element of `string_table`.
--- @param str string The string to search for.
--- @param string_table string[] The table of strings to search in.
--- @return string|nil The matching item from the table, or nil if not found.
function M.str_in_tbl(str, string_table)
	str = vim.trim(str)

	if str == "" then
		return nil
	end

	for _, item in ipairs(string_table) do
		item = vim.trim(item)
		if string.find(str, item, 1, true) then
			return item
		end
	end

	return nil
end

--- Remove an item from a table by value.
--- @param tbl any[] The table to remove from.
--- @param item any The item value to remove.
function M.remove_from_tbl(tbl, item)
	for i, v in ipairs(tbl) do
		if v == item then
			table.remove(tbl, i)
			return
		end
	end
end

--- Join two array-like tables.
--- @param tbl1 any[] The first table (modified in-place).
--- @param tbl2 any[] The second table to append.
--- @return any[] The joined table (tbl1).
function M.join_tables(tbl1, tbl2)
	for _, str in ipairs(tbl2) do
		table.insert(tbl1, str)
	end
	return tbl1
end

--- Generate a unique key for a table by appending a counter to a base key.
--- @param tbl table The table to check for key existence.
--- @param key string The base key.
--- @return string A unique key not present in the table.
function M.get_unique_key(tbl, key)
	local base_key = key
	local counter = 1
	while tbl[key] do
		key = base_key .. tostring(counter)
		counter = counter + 1
	end
	return key
end

return M
