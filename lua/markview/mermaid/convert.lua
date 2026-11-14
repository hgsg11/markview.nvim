--[[
Converts mermaid source to PNG files using an external command.

Files are cached on disk by the hash of the command & the source, so a
diagram is only converted again after it changes.
]]
local convert = {};
local png = require("markview.mermaid.png");

---@type table<string, fun(result: markview.mermaid.png?, err: string?)[]> Callbacks waiting for a conversion, indexed by file path.
convert.pending = {};

---@type table<string, string> Errors from failed conversions, indexed by file path.
convert.errors = {};

---@return string
convert.cache_dir = function ()
	return vim.fs.joinpath(vim.fn.stdpath("cache") --[[ @as string ]], "markview", "mermaid");
end

--- Replaces `{scale}` in `command`.
---@param command string[]
---@param scale number
---@return string[]
convert.command = function (command, scale)
	return vim.tbl_map(function (arg)
		return (arg:gsub("{scale}", tostring(scale)));
	end, command);
end

--- Path of the PNG file for `source`.
---@param source string
---@param command string[]
---@return string
convert.path = function (source, command)
	local hash = vim.fn.sha256(table.concat(command, "\n") .. "\n\n" .. source);
	return vim.fs.joinpath(convert.cache_dir(), hash .. ".png");
end

--- Gets the cached PNG for `source`.
---@param source string
---@param command string[]
---@return markview.mermaid.png? result
---@return string? err Error from a previous conversion.
convert.get = function (source, command)
	local path = convert.path(source, command);
	return png.read(path), convert.errors[path];
end

--- Replaces `{file}` in `command`.
---@param command string[]
---@param file string
---@return string[]
local function expand (command, file)
	return vim.tbl_map(function (arg)
		return (arg:gsub("{file}", file));
	end, command);
end

--- First few lines of an error message, without stack traces.
---@param stderr string
---@return string
local function summarize (stderr)
	local lines = {};

	for _, line in ipairs(vim.split(stderr, "\n", { trimempty = true })) do
		-- Stack frames look like `at fn (file:1:2)` or `fn (https://...:1:2)`.
		if line:match("^%s*at%s") or line:match("%(%S+:%d+:%d+%)%s*$") or #lines >= 5 then
			break;
		end

		table.insert(lines, line);
	end

	return vim.trim(table.concat(lines, "\n"));
end

--- Converts `source` into a PNG file.
---@param source string
---@param command string[]
---@param timeout integer?
---@param on_done fun(result: markview.mermaid.png?, err: string?)
convert.convert = function (source, command, timeout, on_done)
	local path = convert.path(source, command);

	if convert.pending[path] then
		table.insert(convert.pending[path], on_done);
		return;
	end

	local function finish (result, err)
		local callbacks = convert.pending[path] or {};

		convert.pending[path] = nil;
		convert.errors[path] = err;

		for _, callback in ipairs(callbacks) do
			callback(result, err);
		end
	end

	convert.pending[path] = { on_done };

	if vim.fn.executable(command[1]) ~= 1 then
		finish(nil, string.format("`%s` not found. Install it or change `markdown.mermaid.command`.", command[1]));
		return;
	end

	vim.fn.mkdir(convert.cache_dir(), "p");

	--- Write to a temporary file first so that failed conversions don't leave broken files in the cache.
	local tmp = path:gsub("%.png$", ".tmp.png");

	local ok, err = pcall(vim.system, expand(command, tmp), {
		stdin = source,
		text = true,
		timeout = timeout,
	}, function (out)
		vim.schedule(function ()
			if out.code == 0 then
				local result = png.read(tmp);

				if not result then
					vim.uv.fs_unlink(tmp);
					finish(nil, "Command did not produce a PNG file.");
				elseif result.width <= 8 and result.height <= 8 then
					-- Some converters(e.g. `mmdr`) succeed with an empty image for invalid diagrams.
					vim.uv.fs_unlink(tmp);
					finish(nil, "Diagram is empty. Check the mermaid syntax.");
				else
					vim.uv.fs_rename(tmp, path);
					finish(png.read(path), nil);
				end
			else
				vim.uv.fs_unlink(tmp);

				local message = summarize(out.stderr or "");
				finish(nil, message ~= "" and message or string.format("`%s` exited with code %d.", command[1], out.code));
			end
		end);
	end);

	if not ok then
		finish(nil, tostring(err));
	end
end

--- Clears cached errors & files.
convert.clear = function ()
	convert.errors = {};
	vim.fn.delete(convert.cache_dir(), "rf");
end

return convert;
