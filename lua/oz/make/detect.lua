local M = {}
local util = require("oz.util")

--- get build command
---@param project_root string|nil
---@return nil|string
function M.get_build_command(project_root)
	if not project_root or project_root == "" then
		return nil
	end

	if vim.fn.isdirectory(project_root) ~= 1 then
		return nil
	end

	local is_windows = vim.fn.has("win32") == 1

	-- Define build systems to check, in order of preference.
	local build_systems = {
		{ file = "Makefile", command = "make", platform = "any" },
		{ file = "makefile", command = "make", platform = "any" }, -- Case variation
		{ file = "build.ninja", command = "ninja", platform = "any" },

		{ file = "build.sh", command = "./build.sh", platform = "unix" },
		{ file = "build.bat", command = "build.bat", platform = "windows" },
		{ file = "build.cmd", command = "build.cmd", platform = "windows" },

		{ file = "pom.xml", command = "mvn package", platform = "any" }, -- Java Maven
		{ file = "build.gradle", command = "gradle build", platform = "any" }, -- Java/Kotlin Gradle (Groovy)
		{ file = "build.gradle.kts", command = "gradle build", platform = "any" }, -- Java/Kotlin Gradle (Kotlin DSL)
		{ file = "Cargo.toml", command = "cargo build", platform = "any" }, -- Rust Cargo

		{ file = "package.json", command = "npm run build", platform = "any" }, -- Node.js (common convention, assumes 'build' script exists)
		{ file = "CMakeLists.txt", command = "cmake --build ./build", platform = "any" }, -- Assumes out-of-source in './build' dir. Could also be 'make' or 'ninja' in the build dir.
	}

	-- Iterate and check for files
	for _, config in ipairs(build_systems) do
		local file_path = vim.fs.joinpath(project_root, config.file)

		if vim.fn.filereadable(file_path) == 1 then
			local platform_match = false
			if config.platform == "any" then
				platform_match = true
			elseif config.platform == "unix" and not is_windows then
				platform_match = true
			elseif config.platform == "windows" and is_windows then
				platform_match = true
			end

			if platform_match then
				-- Add specific notes for potentially ambiguous commands
				if config.file == "CMakeLists.txt" then
					util.Notify(
						"Note: CMake command assumes './build' directory exists and was configured.",
						"info",
						"oz_make"
					)
				elseif config.file == "package.json" then
					util.Notify("Note: 'npm run build' is a convention; check package.json scripts.", "info", "oz_make")
				end
				return config.command
			end
		end
	end

	return nil
end

return M
