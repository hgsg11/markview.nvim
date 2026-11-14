--[[ Talks to terminals supporting the kitty graphics protocol. ]]
local terminal = {};

--- Does the terminal support the kitty graphics protocol(with unicode placeholders)?
---@return boolean
terminal.supported = function ()
	if vim.env.TMUX or vim.env.ZELLIJ then
		-- NOTE: Multiplexers need passthrough, which isn't supported.
		return false;
	end

	local term = vim.env.TERM or "";
	local program = vim.env.TERM_PROGRAM or "";

	return
		term == "xterm-kitty" or term == "xterm-ghostty" or
		program == "ghostty" or program == "WezTerm" or
		vim.env.KITTY_WINDOW_ID ~= nil or vim.env.GHOSTTY_RESOURCES_DIR ~= nil;
end

---@type { width: number, height: number }?
local cell;

--- Size of a cell in pixels.
---@return number width
---@return number height
terminal.cell_size = function ()
	if cell then
		return cell.width, cell.height;
	end

	--- Used when the terminal doesn't report it's size in pixels.
	cell = { width = 9, height = 18 };

	pcall(function ()
		local ffi = require("ffi");

		pcall(ffi.cdef, [[
			typedef struct {
				unsigned short row;
				unsigned short col;
				unsigned short xpixel;
				unsigned short ypixel;
			} markview_winsize;

			int ioctl(int, unsigned long, ...);
		]]);

		local TIOCGWINSZ = vim.fn.has("mac") == 1 and 0x40087468 or 0x5413;
		local size = ffi.new("markview_winsize");

		if ffi.C.ioctl(1, TIOCGWINSZ, size) == 0 and size.col > 0 and size.row > 0 and size.xpixel > 0 then
			cell = {
				width = size.xpixel / size.col,
				height = size.ypixel / size.row,
			};
		end
	end);

	return cell.width, cell.height;
end

--- Forgets the cached cell size(e.g. after the font size changes).
terminal.reset = function ()
	cell = nil;
end

--- Writes raw data to the terminal.
---@param data string
terminal.write = function (data)
	if vim.api.nvim_ui_send then
		vim.api.nvim_ui_send(data);
	else
		io.stdout:write(data);
		io.stdout:flush();
	end
end

--- Sends a graphics protocol command.
---@param params table<string, string | integer>
---@param payload? string
terminal.command = function (params, payload)
	local keys = vim.tbl_keys(params);
	table.sort(keys);

	local control = {};

	for _, key in ipairs(keys) do
		table.insert(control, key .. "=" .. params[key]);
	end

	terminal.write(string.format(
		"\27_G%s%s\27\\",
		table.concat(control, ","),
		payload and (";" .. payload) or ""
	));
end

return terminal;
