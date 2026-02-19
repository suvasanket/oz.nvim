# oz.nvim

An essential kit for the pragmatic developer who wants their editor to be a bit smarter without losing the feel of Neovim.

Oz is not a collection of wrappers that hide your tools. Instead, it adds a layer of intelligence to your daily workflows: Git, terminal management, building, and searching. It is built to be fast, ensuring a nearly invisible impact on your startup time while staying out of your way until you need it.

## Core Modules
### Git
A comprehensive Git client inspired by the experience of **[Magit](https://magit.vc/)** and the vimness of **[Fugitive](https://github.com/tpope/vim-fugitive)**. It features powerful status and log-viewer, and a "Command Wizard" that catches common git errors and suggests the right command for you, plus a ton more features.

### Term
An enhanced terminal manager that learns. It caches your commands on a per-project and per-directory basis, adapting suggestions to the files you are currently editing. If you run a compiler on `api.c`, Oz will suggest the command adapting to `main.c` when you switch buffers.

### Make
An asynchronous build system that replaces the blocking `:make`. It detects your build environment automatically (Makefile, Cargo, npm, etc.) and keeps the `makeprg` settings synchronized across your projects. With "AutoMake," you can have your tests or builds run automatically as you save.

### Grep
A fast, asynchronous search tool that integrates deeply with Neovim's quickfix list. It supports searching visual ranges, respects your project root by default, and narrows its scope automatically when you are navigating with Oil.

## Installation
Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "suvasanket/oz.nvim",
    opts = {},
}
```
No **mandatory third-party dependencies**.

### Recommended Plugins (Completely optional)
- [fidget.nvim](https://github.com/j-hui/fidget.nvim): For beautiful progress notifications during async tasks.
- [nvim-notify](https://github.com/rcarriga/nvim-notify) (or similar): For enhanced system notifications.
- Any picker for better option picking.

## Feature Showcase
### The Git Experience
The `:Git` (or `:G`) command is your entry point, designed to feel familiar yet more capable.
- **Magit-like Workflow**: Navigate your repository with a powerful status buffer featuring transient keybindings and intuitive section management.
- **Fugitive-like Interface**: Use the `:G` or `:Git` command for asynchronous execution of any git command.
- **Git Wizard**: If you type `:Git puhs` or try to push without an upstream, Oz won't just error out. It will suggest the corrected command in your command line.
- **Async Execution**: Every git command runs in the background. You'll see progressive output for long-running tasks like `push` or `pull`.

### A Smart Terminal
Oz's terminal module is designed to reduce the friction of repetitive tasks.
- **Arbitrary Execution**: Run any shell command with arguments directly via `:Term <cmd>`.
- **Term Wizard**: If no arguments are provided, the Term Wizard suggests the most relevant command based on your learned patterns and project context.
- **Jump & Grab**: Instantly jump to any errors/warnings in the output or use `<C-q>` to grab them all into the quickfix list.
- **Root-Aware**: Use the `@` prefix (e.g., `:Term @make`) to run any command from the project root, regardless of where your current buffer is.

### Project Building
The Make module is about staying in the flow.
- **Project-Specific Caching**: Use `:set makeprg` to set your build command; Oz will automatically cache it (along with your `efm`) for that specific project, restoring it the next time you work there.
- **Root by Default**: Running `:Make` executes from your project root. Use `:Make!` to explicitly run from your current working directory.
- **Transient Keymaps**: While a build is running, temporary global keymaps (`<C-x>` to kill, `<C-d>` to view live execution) are active. They disappear as soon as the job is done.
- **AutoMake**: Use `:AutoMake filetype` or `:AutoMake file` to have Oz automatically trigger a build whenever you save.

### Seamless Search
Grep module is designed to be simple yet effective.
- **Range Support**: Select a block of text and run `:Grep` to search for it across your project. It automatically detects and escapes any wildcards to ensure precise results.
- **Root by Default**: Every search starts from your project root by default. Use `:Grep!` to ground the search to your current working directory.
- **Flexible Flags**: Pass any grep or ripgrep flags directly to the command (e.g., `:Grep -w "pattern"`).

### Integrations
Various modules provides integration with **[oil.nvim](https://github.com/stevearc/oil.nvim)**.
  - **Smart Search**: `:Grep` automatically restricts its search scope to the directory you are currently browsing.
  - **Entry Execution**: Press `<C-G>` over any file or directory to run an arbitrary shell command. `:` separates the cmd and tail (e.g., `cp: /tmp/`: copies entry under cursor to /tmp/). These can be executed as background tasks or in a oz\_term.
  - **Codebase Browsing**: Run `:GBrowse` in an Oil buffer to open that specific directory in your browser at your remote Git host.

> **Tip**: Pressing `g?` in any Oz buffer will instantly bring up the list of all available keybindings for that specific context.

## Configuration
Oz is based on zero-config setup. It works out of the box with sensible defaults and minimal config to keep your environment lean and predictable. Fewer knobs reduce configuration fatigue.

Oz is modular; you can disable any part of it by setting the corresponding key to `false`.

```lua
require("oz").setup({
    -- Git
    oz_git = {
        win_type = "bot",
        mappings = { -- oz_git universal mappings
            toggle_pick = "<C-P>",
            unpick_all = "<C-S-P>",
        },
    },

    -- Term
    oz_term = {
        efm = { "%f:%l:%c: %trror: %m" }, -- strings of errorformats
        root_prefix = "@", -- char to specify command to run in project root
    },

    -- Make
    oz_make = {
        override_make = false, -- override the default :make
        autosave_makeprg = true, -- auto save all the project scoped makeprg(:set makeprg=<cmd>)
        transient_mappings = { -- only unlocks during the execution
            kill_job = "<C-x>",
            toggle_output = "<C-d>",
        },
        -- vim.opt.makeprg can be used to set custom make program
    },

    -- Grep
    oz_grep = {
        override_grep = true, -- override the default :grep
        -- vim.opt.grepprg can be used to set custom grep program
    },

    integration = {
    -- oil integration
        oil = {
            entry_exec = {
                method = "term", -- |background, term|
                use_fullpath = true, -- false: only file or dir name will be used
                tail_prefix = ":", -- split LHS RHS
            },
            mappings = {
                entry_exec = "<C-G>",
                show_keybinds = "g?", -- override existing g?
            },
        },
    },
})
```

## Contributing

If you find a bug or have an idea for a feature that fits the "pragmatic intelligence" philosophy, feel free to open an issue or a pull request.
