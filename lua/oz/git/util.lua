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
		while i <= len and argstring:sub(i, i):match("%s") do
			i = i + 1
		end
		if i > len then
			break
		end
		if argstring:sub(i, i) == '"' or argstring:sub(i, i) == "'" then
			local quote = argstring:sub(i, i)
			local start = i + 1
			i = i + 1
			while i <= len and argstring:sub(i, i) ~= quote do
				i = i + 1
			end

			if i <= len then
				table.insert(args, argstring:sub(start, i - 1))
				i = i + 1
			else
				table.insert(args, argstring:sub(start))
			end
		else
			local start = i
			while i <= len and not argstring:sub(i, i):match("%s") do
				i = i + 1
			end

			table.insert(args, argstring:sub(start, i - 1))
		end
	end

	return args
end

function M.get_remote_cmd(str)
	local git_subcommands = {
		["push"] = { action = "pushing start.", completion = "pushing complete." },
		["pull"] = { action = "pulling start.", completion = "pulling complete." },
		["fetch"] = { action = "fetching start.", completion = "fetching complete." },
		["clone"] = { action = "cloning start.", completion = "cloning complete." },
		["remote"] = { action = "accessing remote", completion = "remote access complete." },
		["ls-remote"] = { action = "connecting to remote repo", completion = "remote connection complete." },
		["archive"] = { action = "archiving started.", completion = "archiving complete." },
		["request-pull"] = { action = "requesting pull.", completion = "pull request complete." },
		["svn"] = { action = "accessing svn.", completion = "svn access complete." },
	}
	if git_subcommands[str] then
		return true, git_subcommands[str].action, git_subcommands[str].completion
	else
		return false, nil, nil
	end
end

return M
