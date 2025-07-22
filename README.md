# inline-git-blame.nvim

VSCode-style inline git blame for Neovim, written in Lua.

Shows commit author, relative time, and commit message at the end of the current line, just like VSCode.
Handles unsaved and uncommitted changes, and only activates on normal files (not on explorer, help, etc).

---

## Features

- Inline blame for the current line
- Shows: **Author, relative time, commit message**
- Displays "You" if the commit author matches your git user
- Handles unsaved and uncommitted changes gracefully
- Skips non-file buffers (NvimTree, Telescope, help, etc.)

---

## Installation

**lazy.nvim:**
```lua
{
  "yt20chill/inline-git-blame.nvim",
  config = function()
    -- Optional: set up a keymap
    vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
  end,
}
```

**packer.nvim:**
```lua
use {
  "yt20chill/inline-git-blame.nvim",
  config = function()
    vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
  end,
}
```

---

## Usage

You can call the blame function manually or map it to a key:

```lua
vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
```

Or trigger it on `CursorHold`:

```lua
vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    require("inline_git_blame").inline_blame_current_line()
  end,
})
```

---

## Requirements

- Neovim 0.8+
- git in your PATH
- Your files must be in a git repository

---

## License

MIT

---
