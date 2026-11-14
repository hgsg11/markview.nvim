# markview.nvim (mermaid fork)

> [!IMPORTANT]
> This is a **fork** of [OXY2DEV/markview.nvim](https://github.com/OXY2DEV/markview.nvim).
> It adds image rendering for `mermaid` code blocks. Everything else follows upstream.
> For general usage & configuration, see the [upstream README](https://github.com/OXY2DEV/markview.nvim#readme).
> Please report issues with the mermaid feature here, not to the upstream project.

## Mermaid diagrams

`mermaid` code blocks are converted to PNG with [mmdr](https://github.com/1jehuang/mermaid-rs-renderer) and shown in place of the source using the [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/#unicode-placeholders) (unicode placeholders).

- Conversion runs asynchronously; converted images are cached in `stdpath("cache")/markview/mermaid`.
- Moving the cursor into the block (hybrid mode) shows the source again.
- If conversion fails, the source stays visible and the error is shown below it.

## Requirements

- Neovim 0.11+
- [mmdr](https://github.com/1jehuang/mermaid-rs-renderer)

  ```sh
  brew tap 1jehuang/mmdr && brew install mmdr
  ```

- A terminal supporting the kitty graphics protocol with unicode placeholders: Ghostty, kitty or WezTerm. tmux & zellij are not supported.

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "hgsg11/markview.nvim",
    lazy = false
}
```

## Configuration

Defaults:

```lua
require("markview").setup({
    markdown = {
        mermaid = {
            enable = true,

            -- `{file}` is replaced with the output path. The source is passed via stdin.
            command = { "mmdr", "-i", "-", "-o", "{file}", "-e", "png" },
            timeout = 10000,

            max_width = 100, -- columns
            max_height = 40, -- rows

            pending_text = "Rendering mermaid diagram...",
            pending_hl = "Comment",
            error_hl = "DiagnosticError",
        }
    }
});
```

## License

[Apache License 2.0](./LICENSE), same as upstream. Original work by [OXY2DEV](https://github.com/OXY2DEV); the mermaid feature (`lua/markview/mermaid/`) was added in this fork.
