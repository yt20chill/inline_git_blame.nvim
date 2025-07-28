package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. package.path

local test_env = {}

function test_env:setup(opts)
	opts = opts or {}
	self.originals = {
		io_popen = _G.io.popen,
		system = vim.fn.system,
		jobstart = vim.fn.jobstart,
		set_extmark = vim.api.nvim_buf_set_extmark,
		get_option_value = vim.api.nvim_get_option_value,
		get_name = vim.api.nvim_buf_get_name,
		getcwd = vim.fn.getcwd,
		fnamemodify = vim.fn.fnamemodify,
		win_get_cursor = vim.api.nvim_win_get_cursor,
		get_current_buf = vim.api.nvim_get_current_buf,
		create_autocmd = vim.api.nvim_create_autocmd,
		buf_clear_namespace = vim.api.nvim_buf_clear_namespace,
		buf_get_extmarks = vim.api.nvim_buf_get_extmarks,
	}
	_G.io.popen = opts.io_popen
		or function(cmd)
			if cmd and cmd:find("rev%-parse") then
				return {
					read = function()
						return "/tmp\n"
					end,
					close = function() end,
				}
			end
			return {
				read = function()
					return ""
				end,
				close = function() end,
			}
		end
	vim.fn.system = opts.system
		or function(cmd)
			if cmd == "git config user.name" then
				return opts.git_user or "test_author"
			end
			return ""
		end
	vim.fn.jobstart = opts.jobstart or vim.fn.jobstart
	vim.api.nvim_buf_set_extmark = opts.set_extmark or vim.api.nvim_buf_set_extmark
	vim.api.nvim_get_option_value = opts.get_option_value or vim.api.nvim_get_option_value
	vim.api.nvim_buf_get_name = opts.get_name or function()
		return "/tmp/test.lua"
	end
	vim.fn.getcwd = opts.getcwd or function()
		return "/tmp"
	end
	vim.fn.fnamemodify = opts.fnamemodify or function(file, _)
		return file
	end
	vim.api.nvim_win_get_cursor = opts.win_get_cursor or function()
		return { 1, 0 }
	end
	vim.api.nvim_get_current_buf = opts.get_current_buf or function()
		return 0
	end
	vim.api.nvim_create_autocmd = opts.create_autocmd or vim.api.nvim_create_autocmd
	vim.api.nvim_buf_clear_namespace = opts.buf_clear_namespace or vim.api.nvim_buf_clear_namespace
	vim.api.nvim_buf_get_extmarks = opts.buf_get_extmarks or vim.api.nvim_buf_get_extmarks
end

function test_env:teardown()
	for k, v in pairs(self.originals) do
		if k == "io_popen" then
			_G.io.popen = v
		elseif k == "system" then
			vim.fn.system = v
		elseif k == "jobstart" then
			vim.fn.jobstart = v
		elseif k == "set_extmark" then
			vim.api.nvim_buf_set_extmark = v
		elseif k == "get_option_value" then
			vim.api.nvim_get_option_value = v
		elseif k == "get_name" then
			vim.api.nvim_buf_get_name = v
		elseif k == "getcwd" then
			vim.fn.getcwd = v
		elseif k == "fnamemodify" then
			vim.fn.fnamemodify = v
		elseif k == "win_get_cursor" then
			vim.api.nvim_win_get_cursor = v
		elseif k == "get_current_buf" then
			vim.api.nvim_get_current_buf = v
		elseif k == "create_autocmd" then
			vim.api.nvim_create_autocmd = v
		elseif k == "buf_clear_namespace" then
			vim.api.nvim_buf_clear_namespace = v
		elseif k == "buf_get_extmarks" then
			vim.api.nvim_buf_get_extmarks = v
		end
	end
end

local blame

describe("inline_git_blame", function()
	before_each(function()
		test_env:setup()
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
		blame.setup({})
	end)
	after_each(function()
		test_env:teardown()
	end)

	it("should show blame for normal, tracked files", function()
		assert.is_true(blame.inline_blame_current_line())
	end)

	it("should show blame for unsaved changes", function()
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
		test_env:setup({
			get_name = function()
				return "/tmp/ignored.lua"
			end,
			io_popen = function()
				return {
					read = function()
						return "/tmp/ignored.lua\n"
					end,
					close = function() end,
				}
			end,
		})
		assert.is_false(blame.inline_blame_current_line())
	end)

	it("should not show blame if buffer has no filename", function()
		test_env:setup({
			get_name = function()
				return ""
			end,
		})
		assert.is_false(blame.inline_blame_current_line())
	end)

	it("should not show blame if file is outside git repo", function()
		test_env:setup({
			get_name = function()
				return "/tmp/not_in_repo.lua"
			end,
			io_popen = function()
				return {
					read = function()
						return ""
					end,
					close = function() end,
				}
			end,
		})
		assert.is_false(blame.inline_blame_current_line())
	end)
end)

describe("setup", function()
	local blame
	local original_create_autocmd
	local autocmd_called

	local function mock_autocmd()
		autocmd_called = false
		original_create_autocmd = vim.api.nvim_create_autocmd
		vim.api.nvim_create_autocmd = function(...)
			autocmd_called = true
			return 1
		end
	end

	local function restore_autocmd()
		vim.api.nvim_create_autocmd = original_create_autocmd
	end

	before_each(function()
		mock_autocmd()
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
	end)

	after_each(function()
		restore_autocmd()
	end)

	it("should set autocmds when debounce_ms > 0", function()
		blame.setup({ debounce_ms = 100 })
		assert.is_true(autocmd_called)
	end)

	it("should not set autocmds when autocmd = false", function()
		blame.setup({ autocmd = false })
		assert.is_false(autocmd_called)
	end)

	it("should not set autocmds when debounce_ms <= 0", function()
		blame.setup({ debounce_ms = 0 })
		assert.is_false(autocmd_called)
		blame.setup({ debounce_ms = -1 })
		assert.is_false(autocmd_called)
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
	local original_clear_namespace

	before_each(function()
		test_env:setup()
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
		cleared_ns_args = nil
		original_clear_namespace = vim.api.nvim_buf_clear_namespace
		vim.api.nvim_buf_clear_namespace = function(bufnr, ns, start, stop)
			cleared_ns_args = { bufnr = bufnr, ns = ns, start = start, stop = stop }
		end
	end)

	after_each(function()
		vim.api.nvim_buf_clear_namespace = original_clear_namespace
		test_env:teardown()
	end)

	it("should clear the namespace for the current buffer", function()
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
	local ns
	local extmarks_called, clear_called, blame_called

	local function mock_blame_api()
		ns = vim.api.nvim_create_namespace("inline_blame")
		vim.api.nvim_get_current_buf = function()
			return bufnr
		end
		vim.api.nvim_win_get_cursor = function()
			return { 2, 0 }
		end -- line 2 (1-indexed)
		vim.api.nvim_buf_get_extmarks = function(buf, ns_id, start, stop, opts)
			extmarks_called = true
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
	end

	before_each(function()
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
		extmarks_called, clear_called, blame_called = false, false, false
		mock_blame_api()
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
	local captured_blame_text

	local function setup_mocks(current_git_user, blame_output)
		test_env:setup({
			system = function(cmd)
				if type(cmd) == "string" and cmd == "git config user.name" then
					return current_git_user
				end
				return ""
			end,
			jobstart = function(cmd, opts)
				vim.schedule(function()
					if cmd[1] == "git" and cmd[4] == "blame" then
						opts.on_stdout(nil, blame_output)
					elseif cmd[1] == "git" and cmd[4] == "show" then
						opts.on_stdout(nil, { "test commit message" })
					end
				end)
			end,
			set_extmark = function(_, _, _, _, opts)
				captured_blame_text = opts.virt_text[1][1]
			end,
			get_option_value = function(opt)
				if opt == "modified" then
					return false
				end
				if opt == "filetype" then
					return "lua"
				end
				if opt == "buftype" then
					return ""
				end
				return ""
			end,
			get_name = function()
				return "/tmp/test.lua"
			end,
			getcwd = function()
				return "/tmp"
			end,
			fnamemodify = function(file, _)
				return file
			end,
			win_get_cursor = function()
				return { 1, 0 }
			end,
			get_current_buf = function()
				return 0
			end,
			io_popen = function(cmd)
				if cmd and cmd:find("rev%-parse") then
					return {
						read = function()
							return "/tmp\n"
						end,
						close = function() end,
					}
				end
				return {
					read = function()
						return ""
					end,
					close = function() end,
				}
			end,
		})
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
	end

	after_each(function()
		test_env:teardown()
		captured_blame_text = nil
	end)

	it("should replace the author with you_label when the author is the current git user", function()
		setup_mocks("test_author", {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		})
		blame.setup({ you_label = "You" })
		blame.inline_blame_current_line()
		vim.wait(20)
		assert.matches("  You", captured_blame_text)
	end)

	it("should not replace the author when the author is not the current git user", function()
		setup_mocks("another_user", {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		})
		blame.setup({ you_label = "You" })
		blame.inline_blame_current_line()
		vim.wait(20)
		assert.matches("  test_author,", captured_blame_text)
	end)

	it("should not replace the author when you_label is nil", function()
		setup_mocks("test_author", {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		})
		blame.setup({ you_label = false })
		blame.inline_blame_current_line()
		vim.wait(20)
		assert.matches("  test_author,", captured_blame_text)
	end)

	it("should show a custom you_label when set", function()
		setup_mocks("test_author", {
			"abcdef1234567890 (test_author 2023-01-01 12:00:00 +0000 1) line content",
			"author test_author",
			"author-time 1672574400",
		})
		blame.setup({ you_label = "Me" })
		blame.inline_blame_current_line()
		vim.wait(20)
		assert.matches("^  Me,", captured_blame_text)
	end)

	it("should show uncommitted changes when blame output is empty", function()
		setup_mocks("test_user", { "" })
		blame.setup({})
		blame.inline_blame_current_line()
		vim.wait(20)
		assert.matches("You • Uncommitted changes", captured_blame_text)
	end)
end)

describe("relative_time", function()
	local blame
	local relative_time

	before_each(function()
		test_env:setup()
		package.loaded["inline_git_blame"] = nil
		blame = require("inline_git_blame")
		relative_time = blame._test_relative_time
		blame.setup({})
	end)

	after_each(function()
		test_env:teardown()
	end)

	it("returns singular for 1 second", function()
		local now = os.time()
		assert.matches("1 second ago", relative_time(now - 1))
	end)

	it("returns plural for 2 seconds", function()
		local now = os.time()
		assert.matches("2 seconds ago", relative_time(now - 2))
	end)

	it("returns singular for 1 minute", function()
		local now = os.time()
		assert.matches("1 minute ago", relative_time(now - 60))
	end)

	it("returns plural for 2 minutes", function()
		local now = os.time()
		assert.matches("2 minutes ago", relative_time(now - 120))
	end)

	it("returns singular for 1 hour", function()
		local now = os.time()
		assert.matches("1 hour ago", relative_time(now - 3600))
	end)

	it("returns plural for 3 hours", function()
		local now = os.time()
		assert.matches("3 hours ago", relative_time(now - 3 * 3600))
	end)

	it("returns 'yesterday' for 1 day ago", function()
		local now = os.time()
		assert.matches("yesterday", relative_time(now - 86400))
	end)

	it("returns singular for 1 day (but not yesterday)", function()
		local now = os.time()
		assert.matches("2 days ago", relative_time(now - 172801))
	end)

	it("returns plural for 5 days", function()
		local now = os.time()
		assert.matches("5 days ago", relative_time(now - 5 * 86400))
	end)

	it("returns singular for 1 month", function()
		local now = os.time()
		assert.matches("1 month ago", relative_time(now - 2592000))
	end)

	it("returns plural for 3 months", function()
		local now = os.time()
		assert.matches("3 months ago", relative_time(now - 3 * 2592000))
	end)

	it("returns singular for 1 year", function()
		local now = os.time()
		assert.matches("1 year ago", relative_time(now - 31536000))
	end)

	it("returns plural for 2 years", function()
		local now = os.time()
		assert.matches("2 years ago", relative_time(now - 2 * 31536000))
	end)

	it("returns unknown for nil input", function()
		assert.equals("unknown", relative_time(nil))
	end)

	it("returns unknown for non-numeric input", function()
		assert.equals("unknown", relative_time("not_a_number"))
	end)
end)

