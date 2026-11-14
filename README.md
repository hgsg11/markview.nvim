# markview.nvim (mermaid fork)

> [!IMPORTANT]
> This is a **fork** of [OXY2DEV/markview.nvim](https://github.com/OXY2DEV/markview.nvim).
> It adds image rendering for `mermaid` code blocks. Everything else follows upstream.
> For general usage & configuration, see the [upstream README](https://github.com/OXY2DEV/markview.nvim#readme).
> Please report issues with the mermaid feature here, not to the upstream project.

## Mermaid diagrams

`mermaid` code blocks are converted to PNG with [mermaid-cli](https://github.com/mermaid-js/mermaid-cli) (`mmdc`) and shown in place of the source using the [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/#unicode-placeholders) (unicode placeholders).

- Conversion runs asynchronously (`mmdc` takes ~1.5s per diagram); converted images are cached in `stdpath("cache")/markview/mermaid`.
- Moving the cursor into the block (hybrid mode) shows the source again.
- If conversion fails, the source stays visible and the error is shown below it.

## Requirements

- Neovim 0.11+
- [mermaid-cli](https://github.com/mermaid-js/mermaid-cli) (`mmdc`)

  ```sh
  npm install -g @mermaid-js/mermaid-cli
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
            -- `{scale}` is replaced with `scale`.
            command = { "mmdc", "-i", "-", "-o", "{file}", "-e", "png", "-s", "{scale}", "-q" },
            timeout = 30000,

            -- Resolution multiplier. Larger values stay sharp when scaled.
            scale = 2,

            -- "auto": diagrams without a direction are converted both
            -- top-to-bottom & left-to-right, and the one shown the largest
            -- in the window is used. `false` to disable.
            direction = "auto",

            -- Images are fit to the window, keeping their aspect ratio.
            max_width = nil, -- columns, defaults to the window width
            max_height = nil, -- rows, defaults to the window height
            max_scale = 2, -- how much small images may be scaled up

            -- `j`/`k` scroll through images that don't fit in the window,
            -- instead of jumping over them.
            scroll = true,

            pending_text = "Rendering mermaid diagram...",
            pending_hl = "Comment",
            error_hl = "DiagnosticError",
        }
    }
});
```

## License

[Apache License 2.0](./LICENSE), same as upstream. Original work by [OXY2DEV](https://github.com/OXY2DEV); the mermaid feature (`lua/markview/mermaid/`) was added in this fork.
