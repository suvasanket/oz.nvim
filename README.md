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
    keys = { "<leader>aa", "<leader>ac", "<leader>av", "<leader>at" },
    cmd = "Term",
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
        Term = "<leader>av",
        TermBang = "<leader>at",
        Compile = "<leader>ac",
        Rerun = "<leader>aa",
    },
    compile = true, -- compile ingration
    oil = true, -- oil integration
}
```
