--[[
Creates variants of a diagram laid out in different directions, so the one
that fits the window best can be used.
]]
local direction = {};

--- Diagrams that take a `direction` statement.
local statement_diagrams = {
	classDiagram = true,
	stateDiagram = true,
	["stateDiagram-v2"] = true,
	erDiagram = true,
};

--- Diagrams that take the direction after the diagram type.
local header_diagrams = {
	flowchart = true,
	graph = true,
};

--- Directions to try.
direction.candidates = { "TB", "LR" };

--- Index of the line with the diagram type.
---@param lines string[]
---@return integer?
local function header_index (lines)
	local in_frontmatter = false;

	for l, line in ipairs(lines) do
		if line:match("^%s*%-%-%-%s*$") then
			in_frontmatter = not in_frontmatter;
		elseif not in_frontmatter and not line:match("^%s*$") and not line:match("^%s*%%%%") then
			return l;
		end
	end
end

--- Variants of `source` for each of `direction.candidates`.
--- Returns `nil` if the diagram doesn't support directions or already sets one.
---@param source string
---@return string[]?
direction.variants = function (source)
	local lines = vim.split(source, "\n", { plain = true });
	local index = header_index(lines);

	if not index then
		return;
	end

	local indent, kind, rest = lines[index]:match("^(%s*)(%S+)(.*)$");

	if statement_diagrams[kind] then
		for _, line in ipairs(lines) do
			if line:match("^%s*direction%s") then
				return;
			end
		end

		return vim.tbl_map(function (dir)
			local copy = vim.list_slice(lines);
			table.insert(copy, index + 1, indent .. "  direction " .. dir);

			return table.concat(copy, "\n");
		end, direction.candidates);
	elseif header_diagrams[kind] then
		if rest:match("^%s*%u%u") then
			-- Direction is already set(e.g. `flowchart TD`).
			return;
		end

		return vim.tbl_map(function (dir)
			local copy = vim.list_slice(lines);
			copy[index] = indent .. kind .. " " .. dir .. rest;

			return table.concat(copy, "\n");
		end, direction.candidates);
	end
end

return direction;
