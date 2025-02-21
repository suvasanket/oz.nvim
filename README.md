# Oz.nvim

## Requirement
- Neovim >= 0.9.4
- [jq](https://github.com/jqlang/jq)
- [compile-mode](https://github.com/ej-shafran/compile-mode.nvim) (optional)

## Installation
lazy:
```lua
{
    "suvasanket/oz.nvim",
    -- uncomment to lazy-load
    -- keys = { "<leader>aa", "<leader>ac", "<leader>av", "<leader>at" },
    -- cmd = "Term",
    event = "VeryLazy",
    dependencies = {
        "ej-shafran/compile-mode.nvim", -- optional
        "stevearc/oil.nvim", -- optional
    },
    opts = {},
}
```

## Config
default config:

```lua
{
    mappings = {
        Term = "<leader>av", -- Open a prompt to execute a shell command in oz_term
        TermBang = "<leader>at", -- Open a prompt to execute a shell command in a tmux window or Neovim tab
        Compile = "<leader>ac", -- Open a prompt to execute a shell command in compile-mode
        Rerun = "<leader>aa", -- Re-execute the previous command (<Term|Compile|TermBang>)
    },

     -- All oz_term options
     oz_term = {
         mappings = {
             open_entry = "<cr>", -- Open the entry (file or directory) under the cursor
             add_to_quickfix = "<C-q>", -- Add any errors, warnings, or stack traces to the quickfix list and jump to the first item
             open_in_compile_mode = "t", -- Run the current command in compile-mode
             rerun = "r", -- Re-execute the previous shell command
             quit = "q", -- Interrupt any shell execution and close the oz_term buffer
             show_keybinds = "g?", -- Show all available keybindings
         },
     },

     -- Compile-mode integration
     compile_mode = {
         mappings = {
             open_in_oz_term = "t", -- Run the current command in oz_term
             show_keybinds = "g?", -- Compile-mode doesn’t provide a keybinding list, so we define one here
         },
     },

     -- Oil integration
     oil = {
         cur_entry_async = true, -- If false, run in oz_term instead of running asynchronously in the background
         cur_entry_fullpath = true, -- If false, only the file or directory name will be used (instead of the full path)
         cur_entry_splitter = "$", -- This character is used to define the pre- and post-entry parts in commands

         mappings = {
             term = "<leader>av", -- Execute a shell command using oz_term
             compile = "<leader>ac", -- Execute a shell command using compile-mode
             cur_entry_cmd = "<C-g>", -- Execute a command on the entry (file or directory) under the cursor
             show_keybinds = "g?", -- Override the existing `g?` mapping
         },
     },
}
```
