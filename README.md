# Oz.nvim
A Neovim plugin collection to turbocharge everyday shell-related workflow.

[oz_git.webm](https://github.com/user-attachments/assets/58229a8d-04a0-43a9-806d-8f175162f1b0)

## Requirement
- Neovim >= 0.9.4
- [neovim-remote](https://github.com/mhinz/neovim-remote) (optional for oz\_git)
- [diffview.nvim](https://github.com/sindrets/diffview.nvim?tab=readme-ov-file) (optional for oz\_git)
- [nvim-notify](https://github.com/rcarriga/nvim-notify) or any notifier plugin (optional)

## Installation
lazy:
```lua
{
    "suvasanket/oz.nvim",
    -- event = "VeryLazy",
    -- dependencies = {
    --     "rcarriga/nvim-notify", -- optional
    --     "j-hui/fidget.nvim", -- optional
    -- },
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
     oz_git = {
         remote_opt_exec = "background", -- |background,term|
         mappings = {
             toggle_pick = "<C-P>",
             unpick_all = "<C-S-P>",
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
     oz_make = {
         override_make = false, -- Override the default :make
         autosave_makeprg = true, -- Auto save all the project scoped makeprg(:set makeprg=<cmd>)
     },

     -- oz_grep options
     oz_grep = {
         override_grep = true, -- override the default :grep
     },

     -- integrations
     integration = {
         -- Compile-mode integration
         compile_mode = {
             mappings = {
                 open_in_oz_term = "t", -- Run the current command in oz_term
                 show_keybinds = "g?", -- Compile-mode doesn’t provide a keymaps list, so we define one here
             },
         },

         -- Oil integration
         oil = {
             entry_exec = {
                 method = "term", -- |background, term|
                 use_fullpath = true, -- Use the full path of the entry
                 lead_prefix = ":", -- char use to specify any lead args/cmds
             },
             mappings = {
                 term = "<global>", -- Execute a shell command using oz_term | by default uses global keys(<leader>av)
                 compile = "<global>", -- Execute a shell command using compile-mode | by default uses global keys(<leader>ac)
                 entry_exec = "<C-G>", -- Execute a command on the entry (file or directory) under the cursor
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

To disable any module: for eg. `oz_git = false`
</details>

## Features
### oz\_term:
#### commands
- `:Term`: like your typical `:term` but interactive by default and some kool keymaps.
    - Using `!` (e.g., `:Term! npm test`) runs the command in the background without stealing focus.
    - Using `@` before the command (e.g., `:Term @make`) runs it from the project root.
- `:TermToggle`: Toggles the visibility of the oz\_term buffer.
- `:TermClose`: Closes any active buffer.
#### keymaps
- “\<leader\>av”(oz\_term with suggestions): shows a prompt to run command using oz\_term.
- “\<leader\>at”: same as above but with `!`.
- “\<leader\>aa”: reruns any previously ran command, supports both oz\_term and [compile-mode.nvim](https://github.com/ej-shafran/compile-mode.nvim)(if installed).
#### command suggestions
- When using `<leader>av`(or any configured map) the most relevant command will be pre-populated based on previous usage.
	- **Context-Aware**: Caches commands on a per-project basis, suggesting the most relevant options for your current filetype and buffer.
	- **Learns Patterns**: Intelligently adapts previous commands to new files. (eg. after running `:Term gcc api.c -o api`, it will suggest `:Term gcc main.c -o main` when you switch to `main.c`)
    - **Oil Integrations**: Caches command on the current directory basis, suggesting the previously ran command in that dir only.

### oz\_make:
#### commands
- `:Make`: a much more improved version of builtin `:make`.
	- **async** by default which means doesn’t block nvim instance.
	- runs from the project root by default, use `!` to run it in the pwd.
	- uses set efm for the current filetype to parse the error or any stdout then add to quickfix list.(More about [‘errorfomat’](https://neovim.io/doc/user/options.html#'errorformat'))
- `:AutoMake`: watches for any changes then automatically runs the `:Make`.
	- `filetype` checks for any changes in the current filetype in any files and runs `:Make`.
	- `file` checks for changes in the current file only and do the same.
#### makeprg
- Supports the built-in `makeprg` option for choosing your build command.(e.g. `:set makeprg=cargo`)
	- Automatically caches the `makeprg` setting per project so you don’t have to reconfigure it each time.
	- Default `makeprg` is make.(ref [‘makeprg’](https://neovim.io/doc/user/options.html#'makeprg'))

### oz\_grep:
#### commands
- `:Grep`: one of the best feature of this plugin, again just like before improving over builtin `:grep`.
	- **Async**, so no blocking.
	- Searches from the root of the project by default, use `!` to  explicitly run in the current directory.
	- Supports passing **flags** and **path** directly as args.
	- Supports both **relative-path notation** and vim's **filename modifiers** for search path specification.
	- Supports **range**, which means you can just visually select something then do `:Grep` to directly search the selected in the whole project.
- Adds all the results to the quickfix list.
#### integrations
- With [oil.nvim](https://github.com/stevearc/oil.nvim), `:Grep` automatically limits its search to your current directory—just navigate where you need and run `:Grep` to instantly narrow the scope.

#### grepprg:
- Use the builtin `grepprg` option to set a grep program.(ref [‘grepprg’](https://neovim.io/doc/user/options.html#'grepprg'))
```lua
vim.o.grepprg = "rg --vimgrep -u -S"
```
- To set a custom format of the specified grep program use the builtin `grepformat` option.(ref [‘grepformat’](https://neovim.io/doc/user/options.html#'grepformat'))

### oz\_git
- The important, huge portion of this plugin and my attempt at creating a git client.
- Unlike other standard Git clients, this one relies on a number of third-party dependencies.
	- oz\_git has very little diffing capabilities, for more you should use [diffview.nvim](https://github.com/sindrets/diffview.nvim?tab=readme-ov-file).
    - [neovim-remote](https://github.com/mhinz/neovim-remote) is a temporary dependency until Neovim’s native remote adds ['wait'](https://neovim.io/doc/user/remote.html#_2.-missing-functionality) support in future release.
    - Tip: use plugins like [minidiff](https://github.com/echasnovski/mini.diff?tab=readme-ov-file) or [gitsigns](https://github.com/lewis6991/gitsigns.nvim) to view changes in the signcolumn and stage or unstage hunks right from your buffer.
#### commands
- `:Git`, `:G`: heavily inspired from [fugitive](https://github.com/tpope/vim-fugitive) but with different philosophy and features.
    - By default when you run a git command its **async**(as usual) and smart.
    - `Git` without args will open the **status** buffer.
    - I’ve aimed to make this self-explanatory, but if anything’s unclear, please check the docs(which ~~might~~ will be available in future).
- `:Gwrite`, `:Gw`: save the current file and stage the changes in the Git repository.
    - to *rename* or *move* the current file pass the path as arg.
- `:Gread`, `:Gr`: revert unstaged changes back without writing.
    - you can explicitly specify any file also as arg.
- `:GitLog`: opens the oz\_git log buffer, showing the full commit history.
    - Like the status buffer, it’s mostly self-explanatory.
    - From the status buffer, press `gl` to open the full log or `gL` on a specific object (branch or file) to view its history.
- `:GBlame`: opens split to the right showing SHA, author, time and line number etc.
    - Not as good as fugitive's but ok enough.
- `:GBrowse`: open the current file or any file you pass as an argument in your browser at your Git host.
    - integrates with [oil.nvim](https://github.com/stevearc/oil.nvim): navigate to a directory and run `:GBrowse` to open that directory in your browser.

## Integrations
