local M = {}

M.buffer_order = {}

local function create_floating_window()
	local width = vim.api.nvim_get_option("columns")
	local height = vim.api.nvim_get_option("lines")

	local win_height = math.ceil(height * 0.33)
	local win_width = math.ceil(width * 0.66)

	local row = math.ceil((height - win_height) / 2 - 1)
	local col = math.ceil((width - win_width) / 2)

	local opts = {
		style = "minimal",
		relative = "editor",
		width = win_width,
		height = win_height,
		row = row,
		col = col,
		border = "rounded",
		title = " Buffers ",
		title_pos = "center",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, opts)

	return buf, win
end

local function get_buffer_list(original_current_buf)
	local buffers = {}

	local valid_buffers = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
			local name = vim.api.nvim_buf_get_name(buf)
			local filename = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
			local is_modified = vim.bo[buf].modified
			local is_current = buf == original_current_buf

			valid_buffers[buf] = {
				bufnr = buf,
				filename = filename,
				fullpath = name,
				modified = is_modified,
				current = is_current,
			}
		end
	end

	local valid_order = {}
	for _, bufnr in ipairs(M.buffer_order) do
		if valid_buffers[bufnr] then
			table.insert(valid_order, bufnr)
		end
	end

	for bufnr, _ in pairs(valid_buffers) do
		local found = false
		for _, ordered_bufnr in ipairs(valid_order) do
			if ordered_bufnr == bufnr then
				found = true
				break
			end
		end
		if not found then
			table.insert(valid_order, bufnr)
		end
	end

	M.buffer_order = valid_order

	for _, bufnr in ipairs(M.buffer_order) do
		table.insert(buffers, valid_buffers[bufnr])
	end

	return buffers
end

local function format_buffer_line(buffer, index)
	local indicator = buffer.current and "●" or "○"
	local modified = buffer.modified and " ●" or ""
	local line = string.format("%s %d: %2d │ %s%s", indicator, index, buffer.bufnr, buffer.filename, modified)
	return line
end

local function refresh_buffer_display(buf, win, buffers, original_current_buf)
	for _, buffer in ipairs(buffers) do
		buffer.current = buffer.bufnr == original_current_buf
	end

	local lines = {}
	for i, buffer in ipairs(buffers) do
		table.insert(lines, format_buffer_line(buffer, i))
	end

	local cursor_pos = vim.api.nvim_win_get_cursor(win)

	vim.bo[buf].readonly = false
	vim.bo[buf].modifiable = true

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	local max_line = #lines
	if cursor_pos[1] > max_line then
		cursor_pos[1] = max_line
	end
	vim.api.nvim_win_set_cursor(win, cursor_pos)
end

local function move_buffer(direction, buf, win, buffers, original_current_buf)
	local current_line = vim.api.nvim_win_get_cursor(win)[1]
	local target_line = current_line + direction

	if target_line < 1 or target_line > #buffers then
		return
	end

	M.buffer_order[current_line], M.buffer_order[target_line] =
		M.buffer_order[target_line], M.buffer_order[current_line]

	buffers[current_line], buffers[target_line] = buffers[target_line], buffers[current_line]

	refresh_buffer_display(buf, win, buffers, original_current_buf)

	vim.api.nvim_win_set_cursor(win, { target_line, 0 })
end

local function setup_buffer(buf)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	vim.wo[0].wrap = false
	vim.wo[0].cursorline = true
end

function M.switch_to_buffer_by_index(index)
	if #M.buffer_order == 0 then
		M.refresh_buffer_order()
	end

	if index > 0 and index <= #M.buffer_order then
		local bufnr = M.buffer_order[index]
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			vim.api.nvim_set_current_buf(bufnr)
		else
			vim.notify(string.format("Buffer %d is not valid", index), vim.log.levels.WARN)
		end
	else
		vim.notify(string.format("No buffer at index %d", index), vim.log.levels.WARN)
	end
end

function M.refresh_buffer_order()
	local current_buf = vim.api.nvim_get_current_buf()
	get_buffer_list(current_buf)
end

function M.show_buffers()
	local original_current_buf = vim.api.nvim_get_current_buf()

	local buffers = get_buffer_list(original_current_buf)
	if #buffers == 0 then
		vim.notify(string.format("No active buffers"), vim.log.levels.WARN)
		return
	end

	local buf, win = create_floating_window()

	setup_buffer(buf)

	refresh_buffer_display(buf, win, buffers, original_current_buf)

	local function close_window()
		vim.api.nvim_win_close(win, true)
	end

	local function goto_buffer()
		local line = vim.api.nvim_win_get_cursor(win)[1]
		if buffers[line] then
			close_window()
			vim.api.nvim_set_current_buf(buffers[line].bufnr)
		end
	end

	local function delete_buffer()
		local line = vim.api.nvim_win_get_cursor(win)[1]
		if buffers[line] then
			local bufnr_to_delete = buffers[line].bufnr

			for i, bufnr in ipairs(M.buffer_order) do
				if bufnr == bufnr_to_delete then
					table.remove(M.buffer_order, i)
					break
				end
			end

			vim.api.nvim_buf_delete(bufnr_to_delete, { force = false })
			close_window()
			M.show_buffers()
		end
	end

	local function move_up()
		move_buffer(-1, buf, win, buffers, original_current_buf)
	end

	local function move_down()
		move_buffer(1, buf, win, buffers, original_current_buf)
	end

	local opts = { buffer = buf, nowait = true, silent = true }
	vim.keymap.set("n", "<CR>", goto_buffer, opts)
	vim.keymap.set("n", "<Esc>", close_window, opts)
	vim.keymap.set("n", "q", close_window, opts)
	vim.keymap.set("n", "d", delete_buffer, opts)
	vim.keymap.set("n", "j", "<Down>", opts)
	vim.keymap.set("n", "k", "<Up>", opts)

	vim.keymap.set("n", "<M-j>", move_down, opts)
	vim.keymap.set("n", "<M-k>", move_up, opts)
	vim.keymap.set("n", "<A-j>", move_down, opts)
	vim.keymap.set("n", "<A-k>", move_up, opts)

	for i = 1, 5 do
		vim.keymap.set("n", tostring(i), function()
			if buffers[i] then
				close_window()
				vim.api.nvim_set_current_buf(buffers[i].bufnr)
			end
		end, opts)
	end
end

function M.get_ordered_buffers()
	return vim.deepcopy(M.buffer_order)
end

function M.set_buffer_order(order)
	M.buffer_order = vim.deepcopy(order)
end

function M.setup(opts)
	opts = opts or {}

	if opts.initial_order then
		M.buffer_order = vim.deepcopy(opts.initial_order)
	end

	vim.api.nvim_create_user_command("BufferFloat", M.show_buffers, {})

	vim.keymap.set("n", "<leader><leader>", M.show_buffers, { desc = "Show floating buffer list" })

	if opts.enable_numbered_keymaps ~= false then
		for i = 1, 5 do
			vim.keymap.set("n", "<leader>" .. i, function()
				M.switch_to_buffer_by_index(i)
			end, { desc = "Switch to buffer " .. i })
		end
	end

	if opts.enable_ordered_navigation then
		vim.keymap.set("n", "]b", function()
			local current = vim.api.nvim_get_current_buf()
			local current_idx = nil
			for i, bufnr in ipairs(M.buffer_order) do
				if bufnr == current then
					current_idx = i
					break
				end
			end
			if current_idx and current_idx < #M.buffer_order then
				vim.api.nvim_set_current_buf(M.buffer_order[current_idx + 1])
			end
		end, { desc = "Next buffer (ordered)" })

		vim.keymap.set("n", "[b", function()
			local current = vim.api.nvim_get_current_buf()
			local current_idx = nil
			for i, bufnr in ipairs(M.buffer_order) do
				if bufnr == current then
					current_idx = i
					break
				end
			end
			if current_idx and current_idx > 1 then
				vim.api.nvim_set_current_buf(M.buffer_order[current_idx - 1])
			end
		end, { desc = "Previous buffer (ordered)" })
	end

	if opts.auto_refresh ~= false then
		vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
			callback = function()
				vim.schedule(function()
					M.refresh_buffer_order()
				end)
			end,
			desc = "Update buffer order when buffers change",
		})
	end
end

return M
