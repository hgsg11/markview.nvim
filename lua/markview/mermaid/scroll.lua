--[[
Lets `j` & `k` scroll through images.

Images are virtual lines below the opening delimiter, so moving the cursor
jumps over them. When the cursor is next to an image that doesn't fit in the
window, these keys scroll the window by a single line instead.
]]
local scroll = {};

---@return integer
local function ns ()
	return require("markview.renderers.markdown").ns;
end

--- Is there an image below `row`?
---@param buffer integer
---@param row integer 0-indexed.
---@return boolean
local function has_image (buffer, row)
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, ns(), { row, 0 }, { row, -1 }, { details = true })) do
		local virt_lines = mark[4].virt_lines;
		local chunk = virt_lines and virt_lines[1] and virt_lines[1][2];

		if chunk and type(chunk[2]) == "string" and chunk[2]:match("^MarkviewMermaidImage") then
			return true;
		end
	end

	return false;
end

--- Image block containing `row`(the opening delimiter or a hidden line).
---@param buffer integer
---@param row integer 0-indexed.
---@return { start: integer, last: integer }? block 0-indexed rows of the opening delimiter & the last hidden line.
local function block_at (buffer, row)
	if has_image(buffer, row) then
		for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, ns(), { row + 1, 0 }, { row + 1, -1 }, { details = true })) do
			if mark[4].conceal_lines and mark[2] == row + 1 then
				return { start = row, last = mark[4].end_row };
			end
		end

		return;
	end

	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, ns(), { row, 0 }, { row, -1 }, { details = true, overlap = true })) do
		if mark[4].conceal_lines and mark[2] <= row and mark[4].end_row >= row and has_image(buffer, mark[2] - 1) then
			return { start = mark[2] - 1, last = mark[4].end_row };
		end
	end
end

--- Moves the cursor to `line`(1-indexed).
---@param line integer
---@return string
local function go_to (line)
	return string.format("<Cmd>%d<CR>", line);
end

--- Number of image rows below the opening delimiter at `row`.
---@param buffer integer
---@param row integer 0-indexed.
---@return integer
local function image_height (buffer, row)
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, ns(), { row, 0 }, { row, -1 }, { details = true })) do
		local virt_lines = mark[4].virt_lines;
		local chunk = virt_lines and virt_lines[1] and virt_lines[1][2];

		if chunk and type(chunk[2]) == "string" and chunk[2]:match("^MarkviewMermaidImage") then
			return #virt_lines;
		end
	end

	return 0;
end

--- Row of `line`(1-indexed) inside the current window, 0 if it isn't visible.
---@param line integer
---@return integer
local function win_row (line)
	local pos = vim.fn.screenpos(0, line, 1);

	if pos.row == 0 then
		return 0;
	end

	return pos.row - vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].winrow + 1;
end

---@return integer
local function win_height ()
	return vim.api.nvim_win_get_height(0);
end

--- Image block at the top of the window, when the opening delimiter is scrolled out.
---@param buffer integer
---@param view vim.fn.winsaveview.ret
---@return { start: integer, last: integer }?
local function scrolled_block (buffer, view)
	local top = view.topline - 1;
	local block = block_at(buffer, top);

	if block and block.start ~= top then
		return block;
	elseif view.topfill > 0 and top > 0 then
		-- The line after the image, with part of the image above it.
		return block_at(buffer, top - 1);
	end
end

--[[
Scrolls the window down by a single screen line.

`<C-e>` skips whole images, so the image rows are turned into filler lines
above the hidden source & removed one at a time.
]]
---@param buffer integer
scroll.down = function (buffer)
	local view = vim.fn.winsaveview();
	local fence = block_at(buffer, view.topline - 1);
	local block;

	if fence and fence.start == view.topline - 1 then
		-- Hide the opening delimiter, keep the whole image visible.
		block = fence;
		view.topline = block.start + 2;
		view.topfill = image_height(buffer, block.start);
	else
		block = scrolled_block(buffer, view);

		if not block then
			vim.cmd("normal! \5");
			return;
		end

		view.topline = block.start + 2;
		view.topfill = math.max(0, math.min(view.topfill, image_height(buffer, block.start)) - 1);

		if view.topfill == 0 then
			view.topline = math.min(block.last + 2, vim.fn.line("$"));
		end
	end

	-- Keep the cursor visible & out of the hidden source.
	local after = block.last + 2;

	if view.lnum - 1 >= block.start and view.lnum - 1 <= block.last and after <= vim.fn.line("$") then
		view.lnum = after;
		view.col = 0;
	end

	vim.fn.winrestview(view);
end

--- Scrolls the window up by a single screen line. See `scroll.down()`.
---@param buffer integer
scroll.up = function (buffer)
	local view = vim.fn.winsaveview();
	local block = scrolled_block(buffer, view);

	if not block and view.topline > 1 then
		-- The line after the image is at the top, start showing the image.
		local above = block_at(buffer, view.topline - 2);

		if above and above.last == view.topline - 2 then
			block = above;
			view.topfill = 0;
		end
	end

	if not block then
		vim.cmd("normal! \25");
		return;
	end

	local height = image_height(buffer, block.start);

	if view.topline - 1 > block.last then
		view.topfill = 0;
	end

	if view.topfill >= height then
		view.topline = block.start + 1;
		view.topfill = 0;
	else
		view.topline = block.start + 2;
		view.topfill = view.topfill + 1;
	end

	vim.fn.winrestview(view);

	-- The cursor was pushed off the bottom.
	if win_row(vim.fn.line(".")) == 0 then
		local fence_row = win_row(block.start + 1);
		vim.api.nvim_win_set_cursor(0, { fence_row > 0 and block.start + 1 or math.min(block.last + 2, vim.fn.line("$")), 0 });
	end
end

--- Is the cursor or the top of the window next to an image?
---@param buffer integer
---@return boolean
local function near_image (buffer)
	local row = vim.fn.line(".") - 1;

	if block_at(buffer, row) or (row > 0 and block_at(buffer, row - 1)) then
		-- On the opening delimiter, a hidden line or the line after the image.
		return true;
	end

	return vim.fn.winsaveview().topfill > 0;
end

--[[
`scrolloff` makes Neovim scroll images back into view to keep lines around
the cursor. Disable it while the cursor is next to an image & restore it
once the cursor moves away.
]]
---@param buffer integer
---@param force? boolean Disable `scrolloff` even if the cursor isn't next to an image yet.
scroll.update_scrolloff = function (buffer, force)
	local win = vim.api.nvim_get_current_win();
	local saved = vim.w[win].markview_mermaid_scrolloff;

	if force or near_image(buffer) then
		if saved == nil then
			vim.w[win].markview_mermaid_scrolloff = vim.api.nvim_get_option_value("scrolloff", { scope = "local", win = win });
			vim.api.nvim_set_option_value("scrolloff", 0, { scope = "local", win = win });
		end
	elseif saved ~= nil then
		vim.api.nvim_set_option_value("scrolloff", saved, { scope = "local", win = win });
		vim.w[win].markview_mermaid_scrolloff = nil;
	end
end

--- Runs `keys` with `scrolloff` disabled.
---@param buffer integer
---@param keys string
---@return string
local function without_scrolloff (buffer, keys)
	return string.format("<Cmd>lua require('markview.mermaid.scroll').update_scrolloff(%d, true)<CR>", buffer) .. keys;
end

--- Keys for `scroll.down()` / `scroll.up()`.
---@param fn "down" | "up"
---@param buffer integer
---@return string
local function call (fn, buffer)
	return string.format("<Cmd>lua require('markview.mermaid.scroll').%s(%d)<CR>", fn, buffer);
end

--- Keys the mapping would have run without this plugin.
---@param key string
---@param fallback table Result of `maparg()` before the mapping was set.
---@return string
local function original (key, fallback)
	if vim.tbl_isempty(fallback) or fallback.buffer == 1 then
		return key;
	elseif fallback.callback then
		local result = fallback.callback();
		return fallback.expr == 1 and type(result) == "string" and result or "";
	elseif fallback.expr == 1 then
		return vim.api.nvim_eval(fallback.rhs);
	end

	return vim.api.nvim_replace_termcodes(fallback.rhs, true, true, true);
end

--- Sets `j` & `k` for `buffer`.
---@param buffer integer
scroll.attach = function (buffer)
	if vim.b[buffer].markview_mermaid_scroll then
		return;
	end

	vim.b[buffer].markview_mermaid_scroll = true;

	vim.api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, {
		buffer = buffer,
		callback = function ()
			scroll.update_scrolloff(buffer);
		end
	});

	local fallback_j = vim.fn.maparg("j", "n", false, true);
	local fallback_k = vim.fn.maparg("k", "n", false, true);

	vim.keymap.set("n", "j", function ()
		if vim.v.count == 0 then
			local row = vim.fn.line(".") - 1;
			local block = block_at(buffer, row);

			if block then
				--- 1-indexed line after the image.
				local after = block.last + 2;
				local fence_row = win_row(block.start + 1);

				if row == block.start and fence_row + image_height(buffer, block.start) >= win_height() then
					-- Part of the image(or the line after it) is still hidden.
					return without_scrolloff(buffer, call("down", buffer));
				elseif after <= vim.fn.line("$") then
					-- Skip the hidden source.
					return without_scrolloff(buffer, go_to(after));
				end
			elseif scrolled_block(buffer, vim.fn.winsaveview()) and win_row(vim.fn.line(".")) >= win_height() then
				-- An image is partially visible at the top, scroll it a line at a time.
				return without_scrolloff(buffer, call("down", buffer) .. original("j", fallback_j));
			end
		end

		return original("j", fallback_j);
	end, { buffer = buffer, expr = true, desc = "Down(scrolls through mermaid images)" });

	vim.keymap.set("n", "k", function ()
		if vim.v.count == 0 then
			local row = vim.fn.line(".") - 1;
			local block = block_at(buffer, row) or (row > 0 and block_at(buffer, row - 1)) or nil;

			if block and block.start ~= row then
				if win_row(block.start + 1) == 0 then
					-- The opening delimiter(& part of the image) is still hidden.
					return without_scrolloff(buffer, call("up", buffer));
				end

				-- Skip the hidden source.
				return without_scrolloff(buffer, go_to(block.start + 1));
			elseif win_row(vim.fn.line(".")) == 1 and (scrolled_block(buffer, vim.fn.winsaveview()) or (row > 0 and block_at(buffer, row - 1))) then
				-- An image is partially visible above the cursor, scroll it a line at a time.
				return without_scrolloff(buffer, call("up", buffer));
			end
		end

		return original("k", fallback_k);
	end, { buffer = buffer, expr = true, desc = "Up(scrolls through mermaid images)" });
end

return scroll;
