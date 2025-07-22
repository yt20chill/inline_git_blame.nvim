local M = {}
local ns = vim.api.nvim_create_namespace("inline_blame")
local current_git_user = vim.trim(vim.fn.system("git config user.name"))

function M.clear_blame()
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

local function relative_time(author_time)
  if not author_time then return "unknown" end
  local blame_time = tonumber(author_time)
  if not blame_time then return "unknown" end
  local now = os.time()
  local diff = os.difftime(now, blame_time)
  if diff < 60 then
    return string.format("%d seconds ago", math.floor(diff))
  elseif diff < 3600 then
    return string.format("%d minutes ago", math.floor(diff / 60))
  elseif diff < 86400 then
    return string.format("%d hours ago", math.floor(diff / 3600))
  elseif diff < 172800 then
    return "yesterday"
  elseif diff < 2592000 then
    return string.format("%d days ago", math.floor(diff / 86400))
  elseif diff < 31536000 then
    return string.format("%d months ago", math.floor(diff / 2592000))
  else
    return string.format("%d years ago", math.floor(diff / 31536000))
  end
end

local function is_normal_file()
  local bt = vim.api.nvim_get_option_value("buftype", { buf = 0 })
  local ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
  return bt == "" and ft ~= "NvimTree" and ft ~= "neo-tree" and ft ~= "TelescopePrompt" and ft ~= "help"
end

local function show_blame(bufnr, line, text)
  vim.api.nvim_buf_set_extmark(bufnr, ns, line - 1, 0, {
    virt_text = { { "  " .. text, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

local function handle_blame_output(bufnr, line, root, sha, author, author_time)
  if author == "Not Committed Yet" then
    vim.schedule(function()
      show_blame(bufnr, line, "You • Uncommitted changes")
    end)
    return
  end
  if not (sha and author and author_time) then
    return
  end
  -- Use "You" if author matches current git user
  local display_author = (author == current_git_user) and "You" or author
  local show_cmd = { "git", "-C", root, "show", "-s", "--format=%s", sha }
  vim.fn.jobstart(show_cmd, {
    stdout_buffered = true,
    on_stdout = function(_, msgdata)
      if not msgdata or not msgdata[1] then
        return
      end
      local rel = relative_time(author_time)
      local msg = msgdata[1]
      vim.schedule(function()
        show_blame(bufnr, line, display_author .. ", " .. rel .. " • " .. msg)
      end)
    end,
  })
end

function M.inline_blame_current_line()
  if not is_normal_file() then
    return
  end
  M.clear_blame()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_option(bufnr, "modified") then
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    show_blame(bufnr, line, "You • Unsaved changes")
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then return end
  local root = vim.fn.getcwd()
  local relfile = vim.fn.fnamemodify(file, ":.")
  local blame_cmd = { "git", "-C", root, "blame", "--porcelain", "-L", line .. "," .. line, relfile }
  vim.fn.jobstart(blame_cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data or #data == 0 or (data[1] == "") then
        vim.schedule(function()
          show_blame(bufnr, line, "You • Uncommitted changes")
        end)
        return
      end
      local sha, author, author_time
      for _, l in ipairs(data) do
        if not sha then sha = l:match("^(%w+) ") end
        if l:find("^author ") then author = l:sub(8) end
        if l:find("^author%-time ") then
          author_time = tonumber(l:sub(13))
        end
      end
      handle_blame_output(bufnr, line, root, sha, author, author_time)
    end,
  })
end

return M