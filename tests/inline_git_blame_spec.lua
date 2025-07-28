package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. package.path

local original_io_popen = io.popen

describe("inline_git_blame", function()
	local blame

	before_each(function()
		-- Patch io.popen to always return not gitignored for main tests
		_G.io.popen = function()
			return {
				read = function()
					return ""
				end,
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
		vim.api.nvim_buf_get_name = function()
			return "/tmp/test.lua"
		end
		vim.fn.getcwd = function()
			return "/tmp"
		end
		vim.fn.fnamemodify = function(file, _)
			return file
		end
		local fake_handle = {
			read = function()
				return ""
			end, -- Simulate not gitignored
			close = function() end,
		}
		_G.io.popen = function()
			return fake_handle
		end

		assert.is_true(blame.inline_blame_current_line())
	end)

	it("should show blame for unsaved changes", function()
		vim.bo.filetype = "lua"
		vim.bo.buftype = ""
		vim.api.nvim_buf_get_name = function()
			return "/tmp/test.lua"
		end
		vim.fn.getcwd = function()
			return "/tmp"
		end
		vim.fn.fnamemodify = function(file, _)
			return file
		end
		_G.io.popen = function()
			return {
				read = function()
					return ""
				end,
				close = function() end,
			}
		end
		local original_get_option_value = vim.api.nvim_get_option_value
		vim.api.nvim_get_option_value = function(opt, opts)
			if opt == "modified" then
				return true
			end
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
		vim.api.nvim_buf_get_name = function()
			return "/tmp/ignored.lua"
		end
		vim.fn.getcwd = function()
			return "/tmp"
		end
		vim.fn.fnamemodify = function(file, _)
			return file
		end
		local fake_handle = {
			read = function()
				return "/tmp/ignored.lua\n"
			end, -- Simulate git check-ignore output
			close = function() end,
		}
		_G.io.popen = function()
			return fake_handle
		end

		assert.is_false(blame.inline_blame_current_line())
	end)

	it("should not show blame if buffer has no filename", function()
		vim.api.nvim_buf_get_name = function()
			return ""
		end
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
			called = true
			return 1
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
			called = true
			return 1
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

describe("toggle_blame_current_line", function()
	local blame
	local bufnr = 1
	local ns = nil
	local extmarks_called = false
	local clear_called = false
	local blame_called = false

	before_each(function()
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
		ns = vim.api.nvim_create_namespace("inline_blame")
		-- Mock extmarks, clear_blame, and inline_blame_current_line
		vim.api.nvim_get_current_buf = function()
			return bufnr
		end
		vim.api.nvim_win_get_cursor = function()
			return { 2, 0 }
		end -- line 2 (1-indexed)
		clear_called = false
		blame_called = false
		extmarks_called = false
		vim.api.nvim_buf_get_extmarks = function(buf, ns_id, start, stop, opts)
			extmarks_called = true
			-- Simulate: if extmarks exist, return a non-empty table
			if _G._test_extmarks_exist then
				return { { 1, 0, {} } }
			else
				return {}
			end
		end
		blame.clear_blame = function()
			clear_called = true
		end
		blame.inline_blame_current_line = function()
			blame_called = true
		end
	end)

	it("clears blame if extmarks exist", function()
		_G._test_extmarks_exist = true
		blame.toggle_blame_current_line()
		assert.is_true(extmarks_called)
		assert.is_true(clear_called)
		assert.is_false(blame_called)
	end)

	it("shows blame if extmarks do not exist", function()
		_G._test_extmarks_exist = false
		blame.toggle_blame_current_line()
		assert.is_true(extmarks_called)
		assert.is_false(clear_called)
		assert.is_true(blame_called)
	end)
end)

describe("you_label", function()
	local blame

	local function setup_mocks(current_git_user, blame_output)
		local original_system = vim.fn.system
		vim.fn.system = function(cmd)
			if type(cmd) == "string" and cmd == "git config user.name" then
				return current_git_user
			end
			return ""
		end

		local original_jobstart = vim.fn.jobstart
		vim.fn.jobstart = function(cmd, opts)
			vim.schedule(function()
				if cmd[1] == "git" and cmd[4] == "blame" then
					opts.on_stdout(nil, blame_output)
				elseif cmd[1] == "git" and cmd[4] == "show" then
					opts.on_stdout(nil, { "test commit message" })
				end
			end)
		end

		local captured_blame_text
		local original_set_extmark = vim.api.nvim_buf_set_extmark
		vim.api.nvim_buf_set_extmark = function(bufnr, ns, line, col, opts)
			captured_blame_text = opts.virt_text[1][1]
		end

		local original_get_option_value = vim.api.nvim_get_option_value
		vim.api.nvim_get_option_value = function(opt, opts_arg)
			if opt == "modified" then
				return false
			end
			if opt == "filetype" then
				return "lua"
			end
			if opt == "buftype" then
				return ""
			end
			return original_get_option_value(opt, opts_arg)
		end

		local original_get_name = vim.api.nvim_buf_get_name
		vim.api.nvim_buf_get_name = function()
			return "/tmp/test.lua"
		end
		local original_getcwd = vim.fn.getcwd
		vim.fn.getcwd = function()
			return "/tmp"
		end
		local original_fnamemodify = vim.fn.fnamemodify
		vim.fn.fnamemodify = function(file, _)
			return file
		end
		local original_popen = _G.io.popen
		_G.io.popen = function()
			return {
				read = function()
					return ""
				end,
				close = function() end,
			}
		end
		local original_get_cursor = vim.api.nvim_win_get_cursor
		vim.api.nvim_win_get_cursor = function()
			return { 1, 0 }
		end
		local original_get_buf = vim.api.nvim_get_current_buf
		vim.api.nvim_get_current_buf = function()
			return 0
		end

		return function()
			vim.fn.system = original_system
			vim.fn.jobstart = original_jobstart
			vim.api.nvim_buf_set_extmark = original_set_extmark
			vim.api.nvim_get_option_value = original_get_option_value
			vim.api.nvim_buf_get_name = original_get_name
			vim.fn.getcwd = original_getcwd
			vim.fn.fnamemodify = original_fnamemodify
			_G.io.popen = original_popen
			vim.api.nvim_win_get_cursor = original_get_cursor
			vim.api.nvim_get_current_buf = original_get_buf
			return captured_blame_text
		end
	end

	before_each(function()
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
	end)

	it("should replace the author with you_label when the author is the current git user", function()
		local blame_output = {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		}
		local cleanup = setup_mocks("test_author", blame_output)
		blame.setup({ you_label = "You" })
		blame.inline_blame_current_line()
		vim.wait(20)
		local captured_blame_text = cleanup()
		assert.matches("  You", captured_blame_text)
	end)

	it("should not replace the author when the author is not the current git user", function()
		local blame_output = {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		}
		local cleanup = setup_mocks("another_user", blame_output)
		blame.setup({ you_label = "You" })
		blame.inline_blame_current_line()
		vim.wait(20)
		local captured_blame_text = cleanup()
		assert.matches("  test_author,", captured_blame_text)
	end)

	it("should not replace the author when you_label is nil", function()
		local blame_output = {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		}
		local cleanup = setup_mocks("test_author", blame_output)
		blame.setup({ you_label = false })
		blame.inline_blame_current_line()
		vim.wait(20)
		local captured_blame_text = cleanup()
		assert.matches("  test_author,", captured_blame_text)
	end)

	it("should show a custom you_label when set", function()
		local blame_output = {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		}
		local cleanup = setup_mocks("test_author", blame_output)
		blame.setup({ you_label = "Me" })
		blame.inline_blame_current_line()
		vim.wait(20)
		local captured_blame_text = cleanup()
		assert.matches("^  Me,", captured_blame_text)
	end)

	it("should show uncommitted changes when blame output is empty", function()
		local cleanup = setup_mocks("test_user", { "" })
		blame.setup({})
		blame.inline_blame_current_line()
		vim.wait(20)
		local captured_blame_text = cleanup()
		assert.matches("You • Uncommitted changes", captured_blame_text)
	end)
end)
