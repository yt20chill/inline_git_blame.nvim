package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. package.path

local original_io_popen = io.popen

describe("inline_git_blame", function()
  local blame

  before_each(function()
    -- Patch io.popen to always return not gitignored for main tests
    _G.io.popen = function()
      return {
        read = function() return "" end,
        close = function() end,
      }
    end
    package.loaded["inline_git_blame"] = nil
    blame = require("inline_git_blame")
    blame.setup({})
  end)

  after_each(function()
    _G.io.popen = original_io_popen
  end)

  it("should show blame for normal, tracked files", function()
    vim.bo.filetype = "lua"
    vim.bo.buftype = ""
    vim.api.nvim_buf_get_name = function() return "/tmp/test.lua" end
    vim.fn.getcwd = function() return "/tmp" end
    vim.fn.fnamemodify = function(file, _) return file end
    local fake_handle = {
      read = function() return "" end, -- Simulate not gitignored
      close = function() end,
    }
    _G.io.popen = function() return fake_handle end

    assert.is_true(blame.inline_blame_current_line())
  end)

  it("should show blame for unsaved changes", function()
    vim.bo.filetype = "lua"
    vim.bo.buftype = ""
    vim.api.nvim_buf_get_name = function() return "/tmp/test.lua" end
    vim.fn.getcwd = function() return "/tmp" end
    vim.fn.fnamemodify = function(file, _) return file end
    _G.io.popen = function() return { read = function() return "" end, close = function() end } end
    local original_get_option_value = vim.api.nvim_get_option_value
    vim.api.nvim_get_option_value = function(opt, opts)
      if opt == "modified" then return true end
      return original_get_option_value(opt, opts)
    end
    assert.is_true(blame.inline_blame_current_line())
    vim.api.nvim_get_option_value = original_get_option_value
  end)

  it("should exclude filetypes in excluded_filetypes", function()
    vim.bo.filetype = "NvimTree"
    assert.is_false(blame.inline_blame_current_line())
  end)

  it("should not blame gitignored files", function()
    vim.api.nvim_buf_get_name = function() return "/tmp/ignored.lua" end
    vim.fn.getcwd = function() return "/tmp" end
    vim.fn.fnamemodify = function(file, _) return file end
    local fake_handle = {
      read = function() return "/tmp/ignored.lua\n" end, -- Simulate git check-ignore output
      close = function() end,
    }
    _G.io.popen = function() return fake_handle end

    assert.is_false(blame.inline_blame_current_line())
  end)

  it("should not show blame if buffer has no filename", function()
    vim.api.nvim_buf_get_name = function() return "" end
    assert.is_false(blame.inline_blame_current_line())
  end)
end)

describe("setup", function()
  local blame
  local original_create_autocmd
  local called

  before_each(function()
    package.loaded["inline_git_blame"] = nil
    original_create_autocmd = vim.api.nvim_create_autocmd
    called = false
    vim.api.nvim_create_autocmd = function(...)
      called = true; return 1
    end
    blame = require("inline_git_blame")
  end)

  after_each(function()
    vim.api.nvim_create_autocmd = original_create_autocmd
  end)

  it("should set autocmds when debounce_ms > 0", function()
    local called = false
    local original_create_autocmd = vim.api.nvim_create_autocmd
    vim.api.nvim_create_autocmd = function(...)
      called = true; return 1
    end
    blame.setup({ debounce_ms = 100 })
    assert.is_true(called)
    vim.api.nvim_create_autocmd = original_create_autocmd
  end)

  it("should not set autocmds when autocmd = false", function()
    blame.setup({ autocmd = false })
    assert.is_false(called)
  end)

  it("should not set autocmds when debounced_ms <= 0", function()
    blame.setup({ debounce_ms = 0 })
    assert.is_false(called)
    blame.setup({ debounce_ms = -1 })
    assert.is_false(called)
  end)

  it("should respect custom excluded_filetypes", function()
    blame.setup({ excluded_filetypes = { "lua" } })
    vim.bo.filetype = "lua"
    assert.is_false(blame.inline_blame_current_line())
  end)

  it("should extend excluded_filetypes with custom excluded_filetypes", function()
    blame.setup({ excluded_filetypes = { "lua" } })
    vim.bo.filetype = "lua"
    assert.is_false(blame.inline_blame_current_line())
    vim.bo.filetype = "NvimTree"
    assert.is_false(blame.inline_blame_current_line())
  end)
end)

describe("clear_blame", function()
  local blame
  local cleared_ns_args

  before_each(function()
    package.loaded["inline_git_blame"] = nil
    blame = require("inline_git_blame")
    cleared_ns_args = nil
    -- Patch vim.api.nvim_buf_clear_namespace to capture arguments
    vim.api.nvim_buf_clear_namespace = function(bufnr, ns, start, stop)
      cleared_ns_args = { bufnr = bufnr, ns = ns, start = start, stop = stop }
    end
  end)

  it("should clear the namespace for the current buffer", function()
    -- Patch vim.api.nvim_buf_clear_namespace to check call
    local called = false
    vim.api.nvim_buf_clear_namespace = function(bufnr, ns, start, stop)
      called = true
      cleared_ns_args = { bufnr = bufnr, ns = ns, start = start, stop = stop }
    end
    blame.clear_blame()
    assert.is_true(called)
    assert.is_table(cleared_ns_args)
    assert.equals(0, cleared_ns_args.bufnr)
    assert.is_number(cleared_ns_args.ns)
    assert.equals(0, cleared_ns_args.start)
    assert.equals(-1, cleared_ns_args.stop)
  end)

  it("should not error if called multiple times", function()
    vim.api.nvim_buf_clear_namespace = function() end
    assert.has_no.errors(function()
      blame.clear_blame()
      blame.clear_blame()
    end)
  end)
end)
