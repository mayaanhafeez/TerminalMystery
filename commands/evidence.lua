-- evidence.lua — cat, grep

local World = require("world")

local function cat(state, args)
	if #args == 0 then
		return "Usage: cat <file>     (try `ls` to see what is in this room)"
	end
	local path = args[1]
	local room_id, fname, err = World.resolve_file_path(state.current_room, path)
	if err then
		return "cat: " .. err
	end
	if not fname then
		return "cat: " .. path .. ": is a directory"
	end

	local item = World.get_item(room_id, fname)
	if item then
		if item.mode == "000" then
			return "Permission denied. That document is restricted."
		end
		state.files_read[room_id .. "/" .. fname] = true
		World.check_unlocks(state)
		state.popup_item = item
		state.popup_page = 1
		return item.content
	end
	-- Cross-room path was explicit: just report missing
	if room_id ~= state.current_room then
		return "cat: " .. path .. ": no such file in " .. World.rooms[room_id].name
	end
	-- Plain filename: hint if the file exists elsewhere
	for visited_id in pairs(state.visited) do
		if World.get_item(visited_id, fname) then
			return "Hint: That document is in the " .. World.rooms[visited_id].name .. ", not here."
		end
	end
	return "There is nothing here by that name."
end

local function grep(state, args)
	if #args == 0 then
		return "Usage: grep [flags] <pattern> [file|*|.[^.]*]\n"
			.. "Flags: -r  recursive   -v  invert   -n  line numbers\n"
			.. "       -l  filenames   -a  include hidden files"
	end

	local flags = { r = false, v = false, n = false, l = false, a = false }
	local idx = 1
	while idx <= #args do
		local a = args[idx]
		if a:sub(1, 1) == "-" and #a > 1 and a ~= "--" then
			for c in a:sub(2):gmatch(".") do
				local lc = c:lower()
				if lc == "r" then
					flags.r = true
				elseif lc == "v" then
					flags.v = true
				elseif lc == "n" then
					flags.n = true
				elseif lc == "l" then
					flags.l = true
				elseif lc == "a" then
					flags.a = true
				end
			end
			idx = idx + 1
		else
			break
		end
	end

	local pattern = args[idx]
	if not pattern or pattern == "" then
		return "Usage: grep [flags] <pattern> [file|*|.[^.]*]"
	end
	idx = idx + 1

	local targets = {}
	local glob_visible, glob_hidden = false, false
	for i = idx, #args do
		local a = args[i]
		if a == "*" then
			glob_visible = true
		elseif a == ".[^.]*" or a == ".*" then
			glob_hidden = true
		else
			table.insert(targets, a)
		end
	end

	local needle = pattern:lower()
	local results = {}

	-- Regex-style line anchors: a leading ^ ties the match to the start of the
	-- line, a trailing $ to the end. Everything between stays a literal substring
	-- (no other regex metachars). A $ or ^ anywhere else is matched literally.
	local anchor_start, anchor_end = false, false
	if needle:sub(1, 1) == "^" then
		anchor_start = true
		needle = needle:sub(2)
	end
	if needle ~= "" and needle:sub(-1) == "$" then
		anchor_end = true
		needle = needle:sub(1, -2)
	end

	local function raw_hit(line)
		local l = line:lower()
		if needle == "" then
			return true -- a bare ^ or $ matches every line, like real grep
		elseif anchor_start and anchor_end then
			return l == needle
		elseif anchor_start then
			return l:sub(1, #needle) == needle
		elseif anchor_end then
			return #l >= #needle and l:sub(-#needle) == needle
		end
		return l:find(needle, 1, true) ~= nil
	end

	local function match(line)
		local hit = raw_hit(line)
		return flags.v and not hit or (not flags.v and hit)
	end

	local function search_one(room_id, item, line_prefix)
		local linenum = 0
		for line in (item.content .. "\n"):gmatch("([^\n]*)\n") do
			linenum = linenum + 1
			if match(line) then
				local prefix = line_prefix
				if flags.n then
					prefix = prefix .. linenum .. ": "
				end
				table.insert(results, prefix .. line)
			end
		end
	end

	local function items_for_room(room_id)
		local include_hidden = flags.a or glob_hidden
		local all = World.get_items_in_room(room_id, include_hidden)
		if glob_visible or glob_hidden or #targets == 0 then
			local out = {}
			for _, it in ipairs(all) do
				local is_hidden = it.hidden == true
				if
					(glob_visible and not is_hidden)
					or (glob_hidden and is_hidden)
					or (not glob_visible and not glob_hidden)
				then
					table.insert(out, it)
				end
			end
			return out
		end
		return all
	end

	if flags.r then
		local room_ids = {}
		for id in pairs(state.visited) do
			table.insert(room_ids, id)
		end
		table.sort(room_ids)
		for _, room_id in ipairs(room_ids) do
			local items = items_for_room(room_id)
			table.sort(items, function(a, b)
				return a.filename < b.filename
			end)
			for _, it in ipairs(items) do
				if flags.l then
					local label = World.rooms[room_id].name .. "/" .. it.filename
					for line in (it.content .. "\n"):gmatch("([^\n]*)\n") do
						if match(line) then
							table.insert(results, label)
							break
						end
					end
				else
					local prefix = World.rooms[room_id].name .. "/" .. it.filename .. ":  "
					search_one(room_id, it, prefix)
				end
			end
		end
	else
		if glob_visible or glob_hidden then
			local items = items_for_room(state.current_room)
			table.sort(items, function(a, b)
				return a.filename < b.filename
			end)
			for _, it in ipairs(items) do
				if flags.l then
					for line in (it.content .. "\n"):gmatch("([^\n]*)\n") do
						if match(line) then
							table.insert(results, it.filename)
							break
						end
					end
				else
					local prefix = #items > 1 and (it.filename .. ":  ") or ""
					search_one(state.current_room, it, prefix)
				end
			end
		elseif #targets == 0 then
			return "Usage: grep [flags] <pattern> [file|*|.[^.]*]"
		else
			for _, fname in ipairs(targets) do
				local item = World.get_item(state.current_room, fname)
				if not item then
					return "There is nothing here by that name."
				end
				if flags.l then
					for line in (item.content .. "\n"):gmatch("([^\n]*)\n") do
						if match(line) then
							table.insert(results, fname)
							break
						end
					end
				else
					search_one(state.current_room, item, "")
				end
			end
		end
	end

	if #results == 0 then
		return "(no matches)"
	end
	return table.concat(results, "\n")
end

local function find(state, args)
	if #args == 0 then
		return "Usage: find [path] [-name <pattern>]\n"
			.. "  find .                 every file in the rooms you've visited\n"
			.. "  find . -name '*.txt'   glob match on the filename\n"
			.. "  find victim            shorthand: match without -name\n"
			.. "Append -a to include hidden files."
	end

	local fname_pattern = nil
	local include_hidden = false
	local saw_path = false
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "-a" then
			include_hidden = true
		elseif a == "-name" then
			i = i + 1
			if args[i] then
				fname_pattern = args[i]
			end
		elseif a == "." then
			saw_path = true
		else
			fname_pattern = a
		end
		i = i + 1
	end

	-- `find .` with no expression lists everything under the path, as real find
	-- does. A bare `find <pattern>` is the game's shorthand for `-name`.
	if not fname_pattern then
		if not saw_path then
			return "find: missing filename pattern"
		end
		fname_pattern = "*"
	end

	local function fname_matches(fname, pattern)
		local p = pattern:lower()
		local f = fname:lower()
		-- Note the plain flag: the needle is the literal `*`, not the pattern
		-- `%*`. Searching for "%*" plainly never matches, which silently
		-- disabled globbing entirely.
		if p:find("*", 1, true) then
			local lua_pat = "^"
				.. p:gsub("%%", "%%%%")
					:gsub("%.", "%%.")
					:gsub("%+", "%%+")
					:gsub("%-", "%%-")
					:gsub("%^", "%%^")
					:gsub("%$", "%%$")
					:gsub("%(", "%%(")
					:gsub("%)", "%%)")
					:gsub("%[", "%%[")
					:gsub("%]", "%%]")
					:gsub("%*", ".*")
				.. "$"
			return f:match(lua_pat) ~= nil
		end
		return f:find(p, 1, true) ~= nil
	end

	local room_ids = {}
	for id in pairs(state.visited) do
		table.insert(room_ids, id)
	end
	table.sort(room_ids)

	local results = {}
	for _, room_id in ipairs(room_ids) do
		local items = World.get_items_in_room(room_id, include_hidden)
		for _, item in ipairs(items) do
			if fname_matches(item.filename, fname_pattern) then
				table.insert(results, "./" .. World.rooms[room_id].name .. "/" .. item.filename)
			end
		end
	end

	if #results == 0 then
		return "(no matching files in visited rooms)"
	end
	return table.concat(results, "\n")
end

local function diff(state, args)
	if #args < 2 then
		return "Usage: diff <file1> <file2>"
	end
	local fname1, fname2 = args[1], args[2]

	local function find_anywhere(fname)
		local item = World.get_item(state.current_room, fname)
		if item then
			return item, state.current_room
		end
		for room_id in pairs(state.visited) do
			if room_id ~= state.current_room then
				local it = World.get_item(room_id, fname)
				if it then
					return it, room_id
				end
			end
		end
		return nil, nil
	end

	local item1, room1 = find_anywhere(fname1)
	local item2, room2 = find_anywhere(fname2)
	if not item1 then
		return "diff: " .. fname1 .. ": no such file"
	end
	if not item2 then
		return "diff: " .. fname2 .. ": no such file"
	end

	if not state.files_read[room1 .. "/" .. fname1] then
		return "You have not read " .. fname1 .. " yet. Use `cat` first."
	end
	if not state.files_read[room2 .. "/" .. fname2] then
		return "You have not read " .. fname2 .. " yet. Use `cat` first."
	end

	local function split_lines(content)
		local lines = {}
		for line in (content .. "\n"):gmatch("([^\n]*)\n") do
			table.insert(lines, line)
		end
		return lines
	end

	local lines1 = split_lines(item1.content)
	local lines2 = split_lines(item2.content)

	local out = { "--- " .. fname1, "+++ " .. fname2 }
	local has_diff = false
	local max = math.max(#lines1, #lines2)
	for i = 1, max do
		local l1, l2 = lines1[i], lines2[i]
		if l1 ~= l2 then
			has_diff = true
			if l1 ~= nil then
				table.insert(out, "- " .. l1)
			end
			if l2 ~= nil then
				table.insert(out, "+ " .. l2)
			end
		end
	end

	if not has_diff then
		return "(files are identical)"
	end
	return table.concat(out, "\n")
end

-- Replace occurrences of a literal `pattern` in one line with `replacement`.
-- Without `global`, only the first occurrence is replaced (sed default).
-- Returns the rebuilt line and the number of substitutions made.
local function replace_in_line(line, pattern, replacement, global)
    local result = {}
    local pos = 1
    local n = 0
    while true do
        local s, e = line:find(pattern, pos, true)
        if not s then break end
        table.insert(result, line:sub(pos, s - 1))
        table.insert(result, replacement)
        n = n + 1
        pos = e + 1
        if not global then break end
    end
    table.insert(result, line:sub(pos))
    return table.concat(result), n
end

local function sed(state, args)
    if #args == 0 then
        return "Usage: sed [-i] 's/pattern/replacement/[g]' <file>\n"
            .. "  -i   edit the file in place (needs write permission: chmod +w <file>)"
    end

    -- Leading flags (only -i is supported).
    local in_place = false
    local idx = 1
    while args[idx] and args[idx]:sub(1, 1) == "-" and args[idx] ~= "-" do
        if args[idx] == "-i" then
            in_place = true
        else
            return "sed: unknown option: " .. args[idx]
        end
        idx = idx + 1
    end

    local script = args[idx]
    local path   = args[idx + 1]
    if not script or not path then
        return "Usage: sed [-i] 's/pattern/replacement/[g]' <file>"
    end

    -- Parse s<delim>pattern<delim>replacement<delim>[flags]  (delimiter follows 's').
    if script:sub(1, 1) ~= "s" then
        return "sed: only substitution is supported, e.g. sed 's/old/new/'"
    end
    local delim = script:sub(2, 2)
    if delim == "" then
        return "sed: malformed substitution: " .. script
    end
    local body   = script:sub(3)
    local first  = body:find(delim, 1, true)
    local second = first and body:find(delim, first + 1, true)
    if not first or not second then
        return "sed: malformed substitution: " .. script
    end
    local pattern     = body:sub(1, first - 1)
    local replacement = body:sub(first + 1, second - 1)
    local global      = body:sub(second + 1):find("g", 1, true) ~= nil
    if pattern == "" then
        return "sed: empty pattern"
    end

    local room_id, fname, err = World.resolve_file_path(state.current_room, path)
    if err then return "sed: " .. err end
    if not fname then return "sed: " .. path .. ": is a directory" end
    local item = World.get_item(room_id, fname)
    if not item then return "sed: " .. path .. ": no such file" end
    if item.mode == "000" then
        return "sed: " .. fname .. ": Permission denied. That document is restricted."
    end

    local total = 0
    local out_lines = {}
    for line in (item.content .. "\n"):gmatch("([^\n]*)\n") do
        local newline, n = replace_in_line(line, pattern, replacement, global)
        total = total + n
        table.insert(out_lines, newline)
    end
    local new_content = table.concat(out_lines, "\n")

    if in_place then
        if not item.writable then
            return "sed: cannot write " .. fname .. ": Permission denied\n"
                .. "     (try: chmod +w " .. fname .. ")"
        end
        if total == 0 then
            return "sed: " .. fname .. ": no occurrences of \"" .. pattern .. "\"; file unchanged"
        end
        item.content = new_content
        item.edited  = true
        return "sed: edited " .. fname .. " in place ("
            .. total .. " substitution" .. (total == 1 and "" or "s") .. ")"
    end

    return new_content
end

return { cat = cat, grep = grep, find = find, diff = diff, sed = sed }
