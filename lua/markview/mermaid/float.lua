--[[
Shows the diagram of the `mermaid` code block under the cursor in a floating
window(`position = "float"`).

The window is placed below or above the code block(whichever has more room),
so the source stays visible while editing it.
]]
local float = {};

local ns = vim.api.nvim_create_namespace("markview.mermaid.float");

---@class markview.mermaid.float.state
---
---@field win? integer Floating window.
---@field buf? integer Buffer shown in the floating window.

---@type markview.mermaid.float.state
local current = {};

--- `mermaid` code block under the cursor.
---@param buffer integer
---@return { start: integer, last: integer, source: string }? block 0-indexed rows of the delimiters & the text between them.
local function code_block (buffer)
	local cursor = vim.api.nvim_win_get_cursor(0);
	local ok, node = pcall(vim.treesitter.get_node, {
		bufnr = buffer,
		pos = { cursor[1] - 1, cursor[2] },
		lang = "markdown",
		ignore_injections = true,
	});

	while ok and node and node:type() ~= "fenced_code_block" do
		node = node:parent();
	end

	if not ok or not node then
		return;
	end

	local language, source;

	for child in node:iter_children() do
		if child:type() == "info_string" then
			for info in child:iter_children() do
				if info:type() == "language" then
					language = vim.treesitter.get_node_text(info, buffer);
				end
			end
		elseif child:type() == "code_fence_content" then
			source = vim.treesitter.get_node_text(child, buffer);
		end
	end

	if language ~= "mermaid" or not source then
		return;
	end

	local row_start, _, row_end, col_end = node:range();

	return {
		start = row_start,
		last = col_end == 0 and row_end - 1 or row_end,
		source = source:gsub("\n?$", "\n"),
	};
end

--- Row of `row`(0-indexed) inside the current window, 0 if it isn't visible.
---@param row integer
---@return integer
local function win_row (row)
	local pos = vim.fn.screenpos(0, row + 1, 1);

	if pos.row == 0 then
		return 0;
	end

	return pos.row - vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].winrow + 1;
end

--- Closes the floating window.
float.close = function ()
	if current.win and vim.api.nvim_win_is_valid(current.win) then
		pcall(vim.api.nvim_win_close, current.win, true);
	end

	current.win = nil;
end

--- Shows `lines` in the floating window, next to `row`.
---@param row integer 0-indexed.
---@param lines string[]
---@param hl string?
---@param below boolean Show the window below `row`?
local function open (row, lines, hl, below)
	if not current.buf or not vim.api.nvim_buf_is_valid(current.buf) then
		current.buf = vim.api.nvim_create_buf(false, true);
		vim.bo[current.buf].bufhidden = "hide";
	end

	vim.api.nvim_buf_set_lines(current.buf, 0, -1, false, lines);
	vim.api.nvim_buf_clear_namespace(current.buf, ns, 0, -1);

	local width = 1;

	for l, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line));

		if hl then
			vim.api.nvim_buf_set_extmark(current.buf, ns, l - 1, 0, { end_col = #line, hl_group = hl });
		end
	end

	local win_config = {
		relative = "win",
		win = vim.api.nvim_get_current_win(),
		bufpos = { row, 0 },
		anchor = below and "NW" or "SW",
		row = below and 1 or 0,
		col = 0,
		width = width,
		height = #lines,
		border = "rounded",
		style = "minimal",
		focusable = false,
		zindex = 45,
	};

	if current.win and vim.api.nvim_win_is_valid(current.win) then
		vim.api.nvim_win_set_config(current.win, win_config);
	else
		current.win = vim.api.nvim_open_win(current.buf, false, win_config);
		vim.wo[current.win].winhighlight = "NormalFloat:Normal";
	end
end

--- Updates the floating window for the cursor position in `buffer`.
---@param buffer integer
float.update = function (buffer)
	if buffer ~= vim.api.nvim_get_current_buf() then
		return;
	elseif not require("markview.state").buf_attached(buffer) then
		float.close();
		return;
	end

	local mermaid = require("markview.mermaid");
	local config = mermaid.get_config(buffer);
	local block = code_block(buffer);

	if not config or config.position ~= "float" or not block then
		float.close();
		return;
	end

	local results, pending, err = mermaid.images(block.source, config, function ()
		vim.schedule(function ()
			float.update(buffer);
		end);
	end);

	-- Show the window where there's more room, so the source stays visible.
	local height = vim.api.nvim_win_get_height(0);
	local start_row, last_row = win_row(block.start), win_row(block.last);

	local room_above = start_row > 0 and start_row - 1 or 0;
	local room_below = last_row > 0 and height - last_row or 0;
	local below = room_below >= room_above;
	local row = below and block.last or block.start;

	local cursor = vim.api.nvim_win_get_cursor(0)[1] - 1;
	local cursor_row = win_row(cursor);

	if math.max(room_above, room_below) < 0.75 * math.max(cursor_row - 1, height - cursor_row) then
		-- Not enough room around the code block(e.g. it's taller than the window), only keep the cursor line visible.
		room_above, room_below = cursor_row - 1, height - cursor_row;
		below = room_below >= room_above;
		row = cursor;
	end

	if pending then
		open(row, { config.pending_text or "Rendering mermaid diagram..." }, config.pending_hl, below);
		return;
	elseif #results == 0 then
		open(row, vim.split(err or "Conversion failed.", "\n", { trimempty = true }), config.error_hl, below);
		return;
	end

	-- Leave room for the border.
	local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1];
	local max_cols = math.min(config.max_width or math.huge, info.width - info.textoff - 2);
	local max_rows = math.min(config.max_height or math.huge, math.max(room_above, room_below) - 2);

	local lines, hl = mermaid.place(results, config, max_cols, math.max(1, max_rows));
	open(row, lines, hl, below);
end

--- Shows the floating window in `buffer`.
---@param buffer integer
float.attach = function (buffer)
	if vim.b[buffer].markview_mermaid_float then
		return;
	end

	vim.b[buffer].markview_mermaid_float = true;

	-- NOTE: Not updated in insert mode, converting on every key press is too slow.
	vim.api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "InsertLeave", "WinScrolled", "BufEnter" }, {
		buffer = buffer,
		callback = function ()
			float.update(buffer);
		end
	});

	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		buffer = buffer,
		callback = float.close
	});

	float.update(buffer);
end

return float;
