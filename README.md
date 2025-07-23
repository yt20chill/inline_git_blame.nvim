# inline-git-blame.nvim

VSCode-style inline git blame for Neovim, written in Lua.

Shows commit author, relative time, and commit message at the end of the current line, just like VSCode.
Handles unsaved and uncommitted changes, and only activates on normal files (not on explorer, help, etc).

---

## Screenshots

![Inline blame example](assets/commited.png)
![Unsaved change](assets/unsaved.png)
![Uncommited change](assets/uncommited.png)

## Features

- Inline blame for the current line
- Shows: **Author, relative time, commit message**
- Displays "You" if the commit author matches your git user
- Handles unsaved and uncommitted changes gracefully
- Skips non-file buffers (NvimTree, Telescope, help, etc.)
- **Configurable:** Extend the list of excluded filetypes via `excluded_filetypes` option

---

## Installation

**lazy.nvim:**

```lua
-- plugins/inline_git_blame.nvim
return {
  "yt20chill/inline_git_blame.nvim",
  event = "BufReadPost",
  opts = {
    -- You can extend the excluded filetypes (these are added to the defaults)
    excluded_filetypes = { "your-filetype" },
    debounce_ms = 150,
    autocmd = true,
  },
    -- Optional: set up keymaps
  config = function(_, opts)
    require("inline_git_blame").setup(opts)
    vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
    vim.keymap.set("n", "<leader>gB", require("inline_git_blame").clear_blame)
  end,
}
```

**packer.nvim**

```lua
use {
  "yt20chill/inline_git_blame.nvim",
  config = function()
    require("inline_git_blame").setup({
      -- optional config
      excluded_filetypes = { "your-filetype" },
      debounce_ms = 150,
      autocmd = true,
    })
    -- optional keymap
    vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
    vim.keymap.set("n", "<leader>gB", require("inline_git_blame").clear_blame)
  end,
}
```

---

## Usage

### Out of the box

**No setup required!**  
By default, inline blame will appear automatically on `CursorHold` and clear on cursor move, thanks to the built-in autocmds.  
Just install and call:

```lua
require("inline_git_blame").setup()
```

You can also add keymaps if you want:

```lua
vim.keymap.set("n", "<leader>gb", require("inline_git_blame").inline_blame_current_line)
vim.keymap.set("n", "<leader>gB", require("inline_git_blame").clear_blame)
```

---

### Custom autocmds (optional)

If you want to set up autocmds yourself (for custom debounce or behavior), set `autocmd = false` in your config and use:

```lua
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

---

## Options

| Option              | Type      | Default                                                      | Description                                      |
|---------------------|-----------|--------------------------------------------------------------|--------------------------------------------------|
| `debounce_ms`       | `number`  | `150`                                                        | Debounce time for blame in ms                    |
| `excluded_filetypes`| `table`   | `{ "NvimTree", "neo-tree", "TelescopePrompt", "help" }`      | Filetypes to exclude (your values are appended)  |
| `autocmd`           | `boolean` | `true`                                                       | Whether to set up built-in autocmds              |

---

## Requirements

- Neovim 0.8+
- git in your PATH
- Your files must be in a git repository

---

## TODO

- [x] Customizable file type to include or exclude
- [ ] Toggle inline git blame
- [ ] Fix plural time

## License

MIT

---
