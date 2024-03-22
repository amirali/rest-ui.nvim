# rest-ui-nvim

Simple UI for [rest-nvim](https://github.com/rest-nvim/rest.nvim/)
⚠️ Only tested with <=v1.2.1

## Installation
### lazy.nvim
```lua
{
    "amirali/rest-ui.nvim",
    dependencies = {
        "rest-nvim/rest.nvim",
        dependencies = { { "nvim-lua/plenary.nvim" } },
        ft = 'http',
        opts = {},
        tag = 'v1.2.1',
    }
}
```

## Usage
You can simply run `RestUI` command and use it
