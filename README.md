# Oz.nvim
A zero-config task runner for neovim

## Requirement
- Neovim >= 0.9.4

## Installation
lazy:
```lua
{
    "suvasanket/oz.nvim",
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
         bufhidden_behaviour = "prompt", -- |prompt, hide, quit|
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
             term = "<global>", -- Execute a shell command using oz_term | by default uses global keys(<leader>av)
             compile = "<global>", -- Execute a shell command using compile-mode | by default uses global keys(<leader>ac)
             cur_entry_cmd = "<C-g>", -- Execute a command on the entry (file or directory) under the cursor
             show_keybinds = "g?", -- Override the existing `g?` mapping
         },
     },

    -- Asynchronous :make
    async_make = { -- Disable by making it false
        override_make = false, -- Override the default :make
        autosave_makeprg = true, -- Auto save all the project scoped makeprg(:set makeprg=<cmd>)
    },

    -- Asynchronous :grep
    async_grep = { -- Disable by making it false
        override_grep = true, -- override the default :grep
    },

    -- error_formats :help errorformat
    efm = {
        cache_efm = true,
    },
}
```
