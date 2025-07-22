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
  "yt20chill/inline_git_blame.nvim",
  config = function()
    -- Optional: set up a keymap
    vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
    vim.keymap.set("n", "<leader>gB", require("inline_git_blame").clear_blame)
  end,
}
```

---

## Usage

### Recommended: Debounced Inline Blame on CursorHold

**lazy.nvim**

```lua
-- Put it in autocmd.lua
local blame = require("inline_git_blame")
local timer
vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    if timer then timer:stop() timer:close() end
    timer = vim.loop.new_timer()
    timer:start(150, 0, vim.schedule_wrap(function()
      blame.inline_blame_current_line()
    end))
  end,
  desc = "Show inline git blame for current line (debounced)",
})

vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
  callback = function()
    blame.clear_blame()
  end,
  desc = "Clear inline git blame on cursor move",
})
```

This will show blame info after a short delay when you pause the cursor, and clear it as soon as you move.

You can call the blame function manually or map it to a key:

```lua
vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
```

---

## Requirements

- Neovim 0.8+
- git in your PATH
- Your files must be in a git repository

---

## TODO

- [ ] Debounce time as opts

## License

MIT

---
