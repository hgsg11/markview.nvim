--[[ Minimal PNG header reader. ]]
local png = {};

---@class markview.mermaid.png
---
---@field path string Path to the image.
---@field width integer Width in pixels.
---@field height integer Height in pixels.

--- Reads a big-endian unsigned 32-bit integer.
---@param str string
---@param from integer
---@return integer
local function u32 (str, from)
	local a, b, c, d = str:byte(from, from + 3);
	return ((a * 256 + b) * 256 + c) * 256 + d;
end

--- Reads the dimensions of a PNG file.
---@param path string
---@return markview.mermaid.png?
png.read = function (path)
	local file = io.open(path, "rb");

	if not file then
		return;
	end

	--- Signature(8) + IHDR length(4) + IHDR type(4) + width(4) + height(4)
	local header = file:read(24);
	file:close();

	if
		not header or #header < 24 or
		header:sub(1, 8) ~= "\137PNG\r\n\26\n" or
		header:sub(13, 16) ~= "IHDR"
	then
		return;
	end

	return {
		path = path,
		width = u32(header, 17),
		height = u32(header, 21),
	};
end

return png;
