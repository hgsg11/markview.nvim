--[[
Renders `mermaid` code blocks as images.

The diagram is converted to a PNG file by an external command(`mmdr` by default)
& shown with the kitty graphics protocol's unicode placeholders. The source of
the code block is hidden while the image is shown.
]]
local mermaid = {};

local spec = require("markview.spec");
local utils = require("markview.utils");

local convert = require("markview.mermaid.convert");
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

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = image.delete_all
	});
end

--- Shows `lines` below the closing delimiter of the code block.
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

--- Renders a `mermaid` code block.
---@param buffer integer
---@param ns integer
---@param item markview.parsed.markdown.code_blocks
mermaid.render = function (buffer, ns, item)
	---@type markview.config.markdown.mermaid?
	local config = spec.get({ "markdown", "mermaid" }, { fallback = nil, eval_args = { buffer, item } });

	if not config or type(config.command) ~= "table" or #config.command == 0 then
		return;
	elseif #item.text < 3 or not terminal.supported() then
		return;
	end

	setup_autocmds();

	local range = item.range;
	local source = table.concat(item.text, "\n", 2, #item.text - 1) .. "\n";
	local result, err = convert.get(source, config.command);

	if err then
		show_message(buffer, ns, item, err, config.error_hl);
		return;
	elseif not result then
		convert.convert(source, config.command, config.timeout, function ()
			redraw(buffer);
		end);

		if config.pending_text then
			show_message(buffer, ns, item, config.pending_text, config.pending_hl);
		end

		return;
	end

	local win = utils.buf_getwin(buffer);
	local max_cols = config.max_width or 80;

	if win and vim.api.nvim_win_is_valid(win) then
		local info = vim.fn.getwininfo(win)[1];
		max_cols = math.min(max_cols, info.width - info.textoff - range.col_start);
	end

	local cell_width, cell_height = terminal.cell_size();
	local cols, rows = placement.size(result, cell_width, cell_height, math.max(1, max_cols), config.max_height or 40);

	local img = image.get(result);
	image.place(img, cols, rows);

	local hl = placement.hl(img.id);
	local indent = string.rep(" ", range.col_start);
	local virt_lines = {};

	for _, line in ipairs(placement.grid(cols, rows)) do
		table.insert(virt_lines, { { indent }, { line, hl } });
	end

	-- Show the image below the opening delimiter.
	utils.set_extmark(buffer, ns, range.row_start, 0, {
		undo_restore = false, invalidate = true,
		virt_lines = virt_lines,
	});

	-- Hide the source & the closing delimiter.
	utils.set_extmark(buffer, ns, range.row_start + 1, 0, {
		undo_restore = false, invalidate = true,
		end_row = range.row_end - 1,
		conceal_lines = "",
	});
end

--- Removes cached diagrams & images.
mermaid.clear_cache = function ()
	convert.clear();
	image.delete_all();
end

return mermaid;
