--- @class oz.util.editor
local M = {}

-- 1. CONSTANTS & CONFIG
--------------------------------------------------------------------------------
local GLOBAL_HANDLER_NAME = "OzGitEditorHandler" -- The global function name used for RPC

-- 2. THE GHOST SCRIPT GENERATOR
-- This generates the Lua code that the HEADLESS Git editor will run.
--------------------------------------------------------------------------------
--- Generate a temporary Lua script for the headless Neovim to use as a Git editor.
--- @return string script_path Path to the generated script.
local function generate_ghost_script()
	local content = string.format(
		[[
    local server_addr = os.getenv("NVIM_SERVER_ADDRESS")
    local wait_file = os.getenv("NVIM_WAIT_FILE")
    local raw_target = arg[1]

    if not server_addr or not wait_file or not raw_target then
        os.exit(1)
    end

    -- [IMPORTANT] Convert path to absolute.
    -- Git passes relative paths, but the Main Neovim might be in a different CWD.
    local target_file = vim.fn.fnamemodify(raw_target, ":p")

    -- Connect to the Main Neovim instance
    local chan = vim.fn.sockconnect("pipe", server_addr, { rpc = true })
    if chan == 0 then os.exit(1) end

    -- Call the global handler in the Main instance
    local ok, err = pcall(vim.rpcrequest, chan, "nvim_exec_lua",
    "return _G.%s(...)",
    { target_file, wait_file }
)

if not ok then
    io.stderr:write("RPC Error: " .. tostring(err))
    os.exit(1)
end

-- Create Lockfile to signal we are waiting
local f = io.open(wait_file, "w")
if f then f:write("locked"); f:close() end

-- Loop until Main Neovim deletes the lockfile
while vim.fn.filereadable(wait_file) == 1 do
    vim.cmd("sleep 50m")
end

os.exit(0)
]],
		GLOBAL_HANDLER_NAME
	)

	local script_path = os.tmpname() .. ".lua"
	local f = io.open(script_path, "w")
	if f then
		f:write(content)
		f:close()
	end
	return script_path
end

-- 3. THE RPC HANDLER
-- This is exposed globally so the headless instance can call it.
--------------------------------------------------------------------------------
--- @param file_path string Path to the file to edit.
--- @param wait_file_path string Path to the lockfile.
_G[GLOBAL_HANDLER_NAME] = function(file_path, wait_file_path)
	-- Schedule to prevent blocking the RPC channel
	vim.schedule(function()
		-- Open the file requested by Git
		vim.cmd("split " .. vim.fn.fnameescape(file_path))

		local buf = vim.api.nvim_get_current_buf()

		-- Auto-detect filetype (gitcommit, gitrebase, etc.)
		vim.bo[buf].filetype = vim.filetype.match({ filename = file_path }) or "gitcommit"

		-- [CRITICAL] Force buffer to WIPE when closed.
		-- This ensures BufUnload triggers even if 'set hidden' is on.
		vim.bo[buf].bufhidden = "wipe"

		-- When the user closes the buffer, release the lockfile
		vim.api.nvim_create_autocmd("BufUnload", {
			buffer = buf,
			once = true,
			callback = function()
				vim.cmd("sync") -- Flush filesystem
				os.remove(wait_file_path) -- Unlock the background process
			end,
		})
	end)
end

-- 4. PUBLIC API
-- Setup environment for IPC
--------------------------------------------------------------------------------
--- Setup the environment variables needed for Git IPC.
--- @return table env Environment variables.
--- @return function cleanup Cleanup function to remove temporary files.
function M.setup_ipc_env()
	local wait_file = os.tmpname()
	local ghost_script = generate_ghost_script()

	-- Command to invoke the headless Neovim
	local fake_editor = string.format("nvim --clean --headless --noplugin -l %s", ghost_script)

	local env = {
		GIT_EDITOR = fake_editor,
		GIT_SEQUENCE_EDITOR = fake_editor,
		NVIM_SERVER_ADDRESS = vim.v.servername,
		NVIM_WAIT_FILE = wait_file,
	}

	local cleanup = function()
		os.remove(ghost_script)
		-- os.remove(wait_file) -- cleaned up by handler usually, but good practice to ensure
	end

	return env, cleanup
end

return M
