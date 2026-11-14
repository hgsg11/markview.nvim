--[[
Renders `mermaid` code blocks as images.

The diagram is converted to a PNG file by an external command(`mmdc` by default)
& shown with the kitty graphics protocol's unicode placeholders, either in place
of the source, above/below it or in a floating window(see `position`).
]]
local mermaid = {};

local spec = require("markview.spec");
local utils = require("markview.utils");

local convert = require("markview.mermaid.convert");
local direction = require("markview.mermaid.direction");
local image = require("markview.mermaid.image");
local placement = require("markview.mermaid.placement");
local terminal = require("markview.mermaid.terminal");

--- Redraws `buffer` if it's still being previewed.
---@param buffer integer
local function redraw (buffer)
	if vim.api.nvim_buf_is_valid(buffer) and require("markview.state").buf_attached(buffer) then
		require("markview.actions").render(buffer);
	end
end

local autocmds_set = false;

--- Keeps images in sync with the terminal.
local function setup_autocmds ()
	if autocmds_set then
		return;
	end

	autocmds_set = true;
	local group = vim.api.nvim_create_augroup("markview.mermaid", { clear = true });

	-- The terminal may have dropped the images(e.g. after `:suspend` or reattaching the UI).
	vim.api.nvim_create_autocmd({ "VimResume", "UIEnter" }, {
		group = group,
		callback = function ()
			terminal.reset();
			image.invalidate();

			for _, buffer in ipairs(require("markview.state").get_attached_buffers()) do
				redraw(buffer);
			end
		end
	});

	-- Images are fit to the window, so resize them along with it.
	vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function ()
			local buffers = {};

			for _, win in ipairs(vim.v.event.windows or {}) do
				if vim.api.nvim_win_is_valid(win) then
					buffers[vim.api.nvim_win_get_buf(win)] = true;
				end
			end

			for buffer, _ in pairs(buffers) do
				redraw(buffer);
			end
		end
	});

	-- The cell size changes along with the font size.
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function ()
			terminal.reset();

			for _, buffer in ipairs(require("markview.state").get_attached_buffers()) do
				redraw(buffer);
			end
		end
	});

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = image.delete_all
	});
end

--- Shows `text` below the closing delimiter of the code block.
---@param buffer integer
---@param ns integer
---@param item markview.parsed.markdown.code_blocks
---@param text string
---@param hl string?
local function show_message (buffer, ns, item, text, hl)
	local indent = string.rep(" ", item.range.col_start);
	local virt_lines = {};

	for _, line in ipairs(vim.split(text, "\n", { trimempty = true })) do
		table.insert(virt_lines, { { indent }, { line, hl } });
	end

	utils.set_extmark(buffer, ns, item.range.row_end - 1, 0, {
		undo_restore = false, invalidate = true,
		virt_lines = virt_lines,
	});
end

---@return markview.config.markdown.mermaid?
mermaid.get_config = function (buffer, item)
	---@type markview.config.markdown.mermaid?
	local config = spec.get({ "markdown", "mermaid" }, { fallback = nil, eval_args = { buffer, item } });

	if not config or type(config.command) ~= "table" or #config.command == 0 then
		return;
	elseif not terminal.supported() then
		return;
	end

	setup_autocmds();
	return config;
end

--- Converted images for `source`.
---@param source string Text between the delimiters.
---@param config markview.config.markdown.mermaid
---@param on_done fun() Called when a pending conversion finishes.
---@return markview.mermaid.png[] results
---@return boolean pending Is a conversion still running?
---@return string? err Error from a failed conversion.
mermaid.images = function (source, config, on_done)
	local command = convert.command(config.command, config.scale or 2);

	--- Sources to convert. With `direction = "auto"`, one for each layout direction.
	local sources = (config.direction == "auto" and direction.variants(source)) or { source };

	local results = {};
	local first_err, pending = nil, false;

	for _, variant in ipairs(sources) do
		local result, err = convert.get(variant, command);

		if result then
			table.insert(results, result);
		elseif err then
			first_err = first_err or err;
		else
			pending = true;
			convert.convert(variant, command, config.timeout, on_done);
		end
	end

	return results, pending, first_err;
end

--- Places the image(out of `results`) that is shown the largest within `max_cols` x `max_rows`.
---@param results markview.mermaid.png[]
---@param config markview.config.markdown.mermaid
---@param max_cols integer
---@param max_rows integer
---@return string[] lines Placeholder text for each row.
---@return string hl Highlight group for the placeholder text.
mermaid.place = function (results, config, max_cols, max_rows)
	local cell_width, cell_height = terminal.cell_size();
	local result, cols, rows;

	for _, candidate in ipairs(results) do
		local c, r = placement.size(candidate, cell_width, cell_height, math.max(1, max_cols), math.max(1, max_rows), config.max_scale);

		if not result or c * r > cols * rows then
			result, cols, rows = candidate, c, r;
		end
	end

	local img = image.get(result);
	image.place(img, cols, rows);

	return placement.grid(cols, rows), placement.hl(img.id);
end

--- Renders a `mermaid` code block.
---@param buffer integer
---@param ns integer
---@param item markview.parsed.markdown.code_blocks
mermaid.render = function (buffer, ns, item)
	local config = mermaid.get_config(buffer, item);

	if not config or #item.text < 3 then
		return;
	end

	local position = config.position or "overlay";

	if position == "float" then
		-- Shown when the cursor is inside the code block.
		require("markview.mermaid.float").attach(buffer);
		return;
	end

	local range = item.range;
	local source = table.concat(item.text, "\n", 2, #item.text - 1) .. "\n";

	local results, pending, err = mermaid.images(source, config, function ()
		redraw(buffer);
	end);

	if pending then
		if config.pending_text then
			show_message(buffer, ns, item, config.pending_text, config.pending_hl);
		end

		return;
	elseif #results == 0 then
		show_message(buffer, ns, item, err or "Conversion failed.", config.error_hl);
		return;
	end

	-- Fit the image to the window(leaving a line for the line it's attached to).
	local win = utils.buf_getwin(buffer);
	local max_cols, max_rows = config.max_width or 80, config.max_height or 40;

	if win and vim.api.nvim_win_is_valid(win) then
		local info = vim.fn.getwininfo(win)[1];

		max_cols = math.min(config.max_width or math.huge, info.width - info.textoff - range.col_start);
		max_rows = math.min(config.max_height or math.huge, info.height - 1);
	end

	local lines, hl = mermaid.place(results, config, max_cols, max_rows);
	local indent = string.rep(" ", range.col_start);
	local virt_lines = {};

	for _, line in ipairs(lines) do
		table.insert(virt_lines, { { indent }, { line, hl } });
	end

	if position == "below" then
		-- Below the closing delimiter.
		utils.set_extmark(buffer, ns, range.row_end - 1, 0, {
			undo_restore = false, invalidate = true,
			virt_lines = virt_lines,
		});
	elseif position == "above" then
		-- Below the line before the opening delimiter, so that it can be scrolled through like the other positions.
		utils.set_extmark(buffer, ns, math.max(0, range.row_start - 1), 0, {
			undo_restore = false, invalidate = true,
			virt_lines = virt_lines,
			virt_lines_above = range.row_start == 0,
		});
	else
		-- Replace the source with the image.
		utils.set_extmark(buffer, ns, range.row_start, 0, {
			undo_restore = false, invalidate = true,
			virt_lines = virt_lines,
		});

		utils.set_extmark(buffer, ns, range.row_start + 1, 0, {
			undo_restore = false, invalidate = true,
			end_row = range.row_end - 1,
			conceal_lines = "",
		});
	end

	if config.scroll ~= false then
		require("markview.mermaid.scroll").attach(buffer);
	end
end

--- Removes cached diagrams & images.
mermaid.clear_cache = function ()
	convert.clear();
	image.delete_all();
end

return mermaid;
