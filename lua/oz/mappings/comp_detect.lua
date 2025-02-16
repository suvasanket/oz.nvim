local M = {}

function M.detect_compiler(ft)
    -- Directly check if an executable with the filetype name exists
    if vim.fn.executable(ft) == 1 then
        return ft
    end

    -- Try common suffix variations dynamically
    local candidates = { ft .. "c", ft .. "++" }
    for _, candidate in ipairs(candidates) do
        if vim.fn.executable(candidate) == 1 then
            return candidate
        end
    end

    -- Check if there's a compiler script in runtimepath
    local runtime_compiler = vim.fn.globpath(vim.o.runtimepath, "compiler/" .. ft .. ".vim")
    if runtime_compiler ~= "" then
        return ft -- Assume filetype name matches compiler name
    end

    return nil -- No suitable compiler found
end

-- detect any shebang in the file
function M.detect_shebang()
    local first_line = vim.fn.getline(1)
    local shebang_match = first_line:match("^#!%s*(%S+)")
    if shebang_match and vim.fn.executable(shebang_match) == 1 then
        return shebang_match
    end
    return nil
end

-- detect makeprg exist for current ft or not
function M.detect_makeprg(filename)
    local makeprg = vim.fn.getbufvar("%", "&makeprg")

    if makeprg and makeprg ~= "" then
        local file_no_ext = vim.fn.fnamemodify(filename, ":r")
        local file_basename = vim.fn.fnamemodify(filename, ":t")
        local file_dir = vim.fn.fnamemodify(filename, ":h")

        makeprg = makeprg
        :gsub("%%:t:r", file_no_ext)
        :gsub("%%:t", file_basename)
        :gsub("%%:r", file_no_ext)
        :gsub("%%:p:h", file_dir)
        :gsub("%%", filename)

        return makeprg
    end
    return nil
end

-- predict the compiler then concat with the current file
function M.predict_compiler(current_file, ft)
    local makeprg = M.detect_makeprg(current_file)
    if makeprg == "make" or not makeprg then
        local compiler = M.detect_compiler(ft)
        if compiler then
            return compiler .. " " .. current_file
        else
            return ""
        end
    else
        return makeprg
    end
end

return M
