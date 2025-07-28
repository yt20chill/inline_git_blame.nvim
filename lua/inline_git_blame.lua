local M = {}

local defaults = {
	debounce_ms = 150,
	excluded_filetypes = { "NvimTree", "neo-tree", "TelescopePrompt", "help" },
	autocmd = true,
	you_label = "You", -- or false to disable replacement
}

local function append_excluded_filetypes(opts)
	opts = opts or {}
	local result = vim.deepcopy(defaults.excluded_filetypes)
	opts.excluded_filetypes = opts.excluded_filetypes or {}
	assert(type(opts.excluded_filetypes) == "table", "excluded_filetypes must be a table")
	for _, ft in ipairs(opts.excluded_filetypes) do
		if type(ft) == "string" then
			table.insert(result, ft)
		end
	end
	return result
end

function M.setup(opts)
	opts = opts or {}
	M.options = vim.tbl_extend("keep", opts, defaults)
	M.options.excluded_filetypes = append_excluded_filetypes(opts)
	if M.options.autocmd and M.options.debounce_ms > 0 then
		if M._autocmds then
			for _, id in ipairs(M._autocmds) do
				pcall(vim.api.nvim_del_autocmd, id)
			end
		end
		M._autocmds = {}
		local timer
		table.insert(
			M._autocmds,
			vim.api.nvim_create_autocmd("CursorHold", {
				callback = function()
					if timer then
						timer:stop()
						timer:close()
					end
					timer = vim.loop.new_timer()
					timer:start(
						M.options.debounce_ms,
						0,
						vim.schedule_wrap(function()
							M.inline_blame_current_line()
						end)
					)
				end,
				desc = "Show inline git blame for current line (debounced)",
			})
		)
		table.insert(
			M._autocmds,
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				callback = function()
					M.clear_blame()
				end,
				desc = "Clear inline git blame on cursor move",
			})
		)
	end
end

local ns = vim.api.nvim_create_namespace("inline_blame")

function M.clear_blame()
	vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

local function get_current_buf_and_line(zero_indexed)
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1]
	if zero_indexed then
		line = line - 1
	end
	return bufnr, line
end

local function relative_time(author_time)
	if not author_time then
		return "unknown"
	end
	local blame_time = tonumber(author_time)
	if not blame_time then
		return "unknown"
	end
	local now = os.time()
	local diff = os.difftime(now, blame_time)
	if diff < 60 then
		local n = math.floor(diff)
		return string.format("%d second%s ago", n, n == 1 and "" or "s")
	elseif diff < 3600 then
		local n = math.floor(diff / 60)
		return string.format("%d minute%s ago", n, n == 1 and "" or "s")
	elseif diff < 86400 then
		local n = math.floor(diff / 3600)
		return string.format("%d hour%s ago", n, n == 1 and "" or "s")
	elseif diff < 172800 then
		return "yesterday"
	elseif diff < 2592000 then
		local n = math.floor(diff / 86400)
		return string.format("%d day%s ago", n, n == 1 and "" or "s")
	elseif diff < 31536000 then
		local n = math.floor(diff / 2592000)
		return string.format("%d month%s ago", n, n == 1 and "" or "s")
	else
		local n = math.floor(diff / 31536000)
		return string.format("%d year%s ago", n, n == 1 and "" or "s")
	end
end

local function is_git_ignored()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		return false
	end
	local root = vim.fn.getcwd()
	local relfile = vim.fn.fnamemodify(file, ":.")
	local handle = io.popen(string.format('git -C "%s" check-ignore "%s"', root, relfile))
	if not handle then
		return false
	end
	local result = handle:read("*a")
	handle:close()
	if result and result ~= "" then
		return true
	end
	return false
end

local function is_excluded()
	local ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
	for _, excluded in ipairs(M.options.excluded_filetypes) do
		if ft == excluded then
			return true
		end
	end
	return false
end

local function is_blamable()
	local bt = vim.api.nvim_get_option_value("buftype", { buf = 0 })
	if bt ~= "" or is_git_ignored() then
		return false
	end
	return not is_excluded()
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

	-- Get current git user for comparison
	local current_git_user = vim.trim(vim.fn.system("git config user.name"))
	local display_author = (M.options.you_label and author == current_git_user) and M.options.you_label or author

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
	if not is_blamable() then
		return false
	end
	M.clear_blame()
	local bufnr, line = get_current_buf_and_line(false)
	if vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
		show_blame(bufnr, line, "You • Unsaved changes")
		return true
	end

	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		return false
	end
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
				if not sha then
					sha = l:match("^(%w+) ")
				end
				if l:find("^author ") then
					author = l:sub(8)
				end
				if l:find("^author%-time ") then
					author_time = tonumber(l:sub(13))
				end
			end
			handle_blame_output(bufnr, line, root, sha, author, author_time)
		end,
	})
	return true
end

function M.toggle_blame_current_line()
	local bufnr, line0 = get_current_buf_and_line(true)
	local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { line0, 0 }, { line0, -1 }, {})
	if #extmarks > 0 then
		M.clear_blame()
	else
		M.inline_blame_current_line()
	end
end

M._test_relative_time = relative_time
return M
