local M = {}

local lazy = {
    -- oz.util.tbl
    tbl_insert = "oz.util.tbl",
    str_in_tbl = "oz.util.tbl",
    remove_from_tbl = "oz.util.tbl",
    join_tables = "oz.util.tbl",
    get_unique_key = "oz.util.tbl",

    -- oz.util.fs
    GetProjectRoot = "oz.util.fs",
    is_readable = "oz.util.fs",
    find_valid_path = "oz.util.fs",

    -- oz.util.ui
    echoprint = "oz.util.ui",
    inactive_echo = "oz.util.ui",
    UserInput = "oz.util.ui",
    inactive_input = "oz.util.ui",
    Notify = "oz.util.ui",
    prompt = "oz.util.ui",
    set_cmdline = "oz.util.ui",
    transient_cmd_complete = "oz.util.ui",
    open_url = "oz.util.ui",

    -- hl
    setup_hls = "oz.util.hl",

    -- oz.util.editor_util
    get_visual_selection = "oz.util.editor_util",
    open_in_split = "oz.util.editor_util",

    -- oz.util.misc
    ShellCmd = "oz.util.misc",
    usercmd_exist = "oz.util.misc",
    clear_qflist = "oz.util.misc",
    extract_flags = "oz.util.misc",
    generate_unique_id = "oz.util.misc",
    Map = "oz.util.misc",
    exit_visual = "oz.util.misc",

    -- oz.util.editor
    setup_ipc_env = "oz.util.editor",

    -- oz.util.progress
    start_progress = "oz.util.progress",
    update_progress = "oz.util.progress",
    stop_progress = "oz.util.progress",

    -- oz.util.shell
    run_command = "oz.util.shell",
    shellout_str = "oz.util.shell",
    shellout_tbl = "oz.util.shell",

    -- oz.util.win
    create_win = "oz.util.win",
    create_floating_window = "oz.util.win",
    create_bottom_overlay = "oz.util.win",

    -- oz.util.help_keymaps
    show_maps = "oz.util.help_keymaps",
    show_menu = "oz.util.help_keymaps",
    close = "oz.util.help_keymaps",

    -- oz.util.git
    if_in_git = "oz.util.git",
    get_git_root = "oz.util.git",
    get_branch = "oz.util.git",
    str_contains_hash = "oz.util.git",

    -- oz.util.picker
    pick = "oz.util.picker",

    -- parse
    parse_args = "oz.util.parse_args",

    -- tbl monitor
    start_monitoring = "oz.util.tbl_monitor",
    stop_monitoring = "oz.util.tbl_monitor",
    is_monitoring = "oz.util.tbl_monitor",
    stop_all_monitoring = "oz.util.tbl_monitor",

    -- oz.caching
    set_cache = "oz.caching",
    get_cache = "oz.caching",
    remove_cache = "oz.caching",
}

setmetatable(M, {
    __index = function(t, k)
        -- Legacy/Direct access for specific modules
        if k == "caching" then
            local mod = require("oz.caching")
            t[k] = mod
            return mod
        end

        -- Lazy loading for individual functions
        local mod_path = lazy[k]
        if mod_path then
            local mod = require(mod_path)
            -- Handle renamed functions
            local func_name = k
            if k == "get_git_root" then
                func_name = "get_project_root"
            elseif k == "set_cache" then
                func_name = "set_data"
            elseif k == "get_cache" then
                func_name = "get_data"
            elseif k == "remove_cache" then
                func_name = "remove_oz_json"
            end
            t[k] = mod[func_name]
            return mod[func_name]
        end
    end,
})

return M
