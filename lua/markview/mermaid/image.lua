--[[ Images transmitted to the terminal. ]]
local image = {};
local terminal = require("markview.mermaid.terminal");

---@class markview.mermaid.image
---
---@field id integer Image ID(also used as the foreground color, so it must fit in 24 bits).
---@field png markview.mermaid.png
---@field sent boolean Has the image data been sent to the terminal?
---@field size? [ integer, integer ] Size(columns, rows) of the current virtual placement.

---@type table<string, markview.mermaid.image> Images, indexed by file path.
image.cache = {};

--- Start somewhere random so that images from other Neovim instances aren't overwritten.
local next_id = math.random(1, 0x7FFF) * 256;

---@return integer
local function new_id ()
	next_id = next_id + 1;

	if next_id > 0xFFFFFF then
		next_id = 1;
	end

	return next_id;
end

--- Gets the image for `png`.
---@param png markview.mermaid.png
---@return markview.mermaid.image
image.get = function (png)
	local cached = image.cache[png.path];

	if cached and cached.png.width == png.width and cached.png.height == png.height then
		return cached;
	end

	cached = { id = new_id(), png = png, sent = false };
	image.cache[png.path] = cached;

	return cached;
end

--- Makes the image available as a `cols` x `rows` placeholder grid.
---@param img markview.mermaid.image
---@param cols integer
---@param rows integer
image.place = function (img, cols, rows)
	if not img.sent then
		-- Let the terminal read the file directly.
		terminal.command({ a = "t", t = "f", f = 100, i = img.id, q = 2 }, vim.base64.encode(img.png.path));

		img.sent = true;
		img.size = nil;
	end

	if img.size and img.size[1] == cols and img.size[2] == rows then
		return;
	end

	terminal.command({ a = "p", U = 1, i = img.id, p = 1, c = cols, r = rows, C = 1, q = 2 });
	img.size = { cols, rows };
end

--- Deletes every image from the terminal.
image.delete_all = function ()
	for _, img in pairs(image.cache) do
		if img.sent then
			terminal.command({ a = "d", d = "I", i = img.id, q = 2 });
		end
	end

	image.cache = {};
end

--- Marks every image as not sent(e.g. after the terminal was reset).
image.invalidate = function ()
	for _, img in pairs(image.cache) do
		img.sent = false;
		img.size = nil;
	end
end

return image;
