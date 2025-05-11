# Oz.nvim
A Neovim plugin collection to turbocharge your everyday shell-related workflow.

## Requirement
- Neovim >= 0.9.4
- [neovim-remote](https://github.com/mhinz/neovim-remote) (optional for oz_git)
- [diffview.nvim](https://github.com/sindrets/diffview.nvim?tab=readme-ov-file) (optional for oz_git)
- [nvim-notify](https://github.com/rcarriga/nvim-notify) or any notifier plugin (optional)

## Installation
lazy:
```lua
{
    "suvasanket/oz.nvim",
    -- event = "VeryLazy",
    -- you can load plugins like nvim-notify, diffview.nvim, fidget.nvim etc independently.
    opts = {},
}
```

## Config
<details>
<summary>Default config</summary>

```lua
{
    mappings = {
        Term = "<leader>av", -- Open a prompt to execute a shell command in oz_term
        TermBang = "<leader>at", -- Open a prompt to execute a shell command in a tmux window or Neovim tab
        Rerun = "<leader>aa", -- Re-execute the previous command (<Term|Compile|Term!>)
    },

     -- oz_git options
     oz_git = { -- false: to disable :Git or :G
         remote_operation_exec_method = "background", -- |background,term|
         mappings = {
             toggle_pick = "<Space>",
             unpick_all = "<C-Space>",
         },
     },

     -- oz_term options
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

     -- oz_make options
     oz_make = { -- Disable by making it false
         override_make = false, -- Override the default :make
         autosave_makeprg = true, -- Auto save all the project scoped makeprg(:set makeprg=<cmd>)
     },

     -- oz_grep options
     oz_grep = { -- Disable by making it false
         override_grep = true, -- override the default :grep
     },

     -- integrations
     integration = {
         -- Compile-mode integration
         compile_mode = {
             mappings = {
                 open_in_oz_term = "t", -- Run the current command in oz_term
                 show_keybinds = "g?", -- Compile-mode doesn’t provide a keybinding list, so we define one here
             },
         },

         -- Oil integration
         oil = {
             entry_exec = {
                 method = "async", -- |async, term|
                 use_fullpath = true, -- Use the full path of the entry
                 lead_prefix = ":", -- char use to specify any lead args/cmds
             },
             mappings = {
                 term = "<global>", -- Execute a shell command using oz_term | by default uses global keys(<leader>av)
                 compile = "<global>", -- Execute a shell command using compile-mode | by default uses global keys(<leader>ac)
                 entry_exec = "<C-g>", -- Execute a command on the entry (file or directory) under the cursor
                 show_keybinds = "g?", -- Override the existing `g?` mapping
             },
         },
     }

    -- error_formats :help errorformat
    efm = {
        cache_efm = true,
    },
}
```
</details>
