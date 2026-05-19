-- commands.lua
-- Command parser and handlers. Each handler is (state, args) -> output_string
-- and mutates state in place. No rendering, no LÖVE calls.

local World = require("world")

local M = {}

-- Tokenize input with simple double/single quote support, so a player can
-- write things like:   grep "R.C." torn_letter.txt
local function tokenize(input)
    local tokens = {}
    local i = 1
    local n = #input
    while i <= n do
        while i <= n and input:sub(i, i):match("%s") do
            i = i + 1
        end
        if i > n then break end
        local c = input:sub(i, i)
        if c == '"' or c == "'" then
            local quote = c
            i = i + 1
            local start = i
            while i <= n and input:sub(i, i) ~= quote do
                i = i + 1
            end
            table.insert(tokens, input:sub(start, i - 1))
            i = i + 1  -- skip closing quote (or fall off end)
        else
            local start = i
            while i <= n and not input:sub(i, i):match("%s") do
                i = i + 1
            end
            table.insert(tokens, input:sub(start, i - 1))
        end
    end
    return tokens
end

local handlers = {}

local function locked_message(cmd)
    if cmd == "cat" then
        return "Your hand hovers over the evidence — but you stay it.\n"
            .. "Walk the mansion first. Do not disturb anything until you\n"
            .. "have at least taken the measure of the place."
    elseif cmd == "grep" then
        return "You have nothing yet to cross-reference.\n"
            .. "Read at least two pieces of evidence before you try to\n"
            .. "draw lines between them."
    end
    return "That ability is not yet available to you."
end

-- ---------- helpers ----------

local function room_path(room_id)
    local parts = {}
    local id = room_id
    while id do
        local room = World.rooms[id]
        table.insert(parts, 1, room.id)
        id = room.parent
    end
    -- replace the root segment ("foyer") with "~"
    parts[1] = "~"
    if #parts == 1 then return "~" end
    return table.concat(parts, "/")
end

-- ---------- handlers ----------

function handlers.help(state, _)
    local lines = {
        "Available commands:",
        "  ls                       list the contents of this room",
        "  pwd                      print current room path",
        "  cwd                      print previous room path",
        "  cd <room>                move to an adjacent room",
        "  cd .. / cd ~             go up to the Foyer (root / home)",
        "  cd ../<room>             go up then into a room (e.g. cd ../study)",
        "  cd -                     return to the previous room",
        "  cd                       return to the Foyer",
        "  echo <text>              repeat text back",
        "  exit                     quit the game",
        "  help                     show this list",
        "  accuse <name>            name the murderer",
    }
    table.insert(lines, "  cat <file>               read a piece of evidence")
    if state.unlocked.grep then
        table.insert(lines,
            "  grep <pattern> <file>    search one file for a pattern")
        table.insert(lines,
            "  grep -r <pattern>        search every file in every room you have visited")
    else
        table.insert(lines,
            "  grep ...                 (not yet — read two pieces of evidence first)")
    end
    table.insert(lines, "")
    table.insert(lines, "Tip: filenames you find with `ls` are case-sensitive.")
    table.insert(lines, "Tip: `accuse` takes a surname or a full name.")
    return table.concat(lines, "\n")
end

function handlers.ls(state, _)
    local room = World.rooms[state.current_room]
    local out = {}
    table.insert(out, "-- " .. room.name .. " --")
    table.insert(out, "Exits:")
    for _, exit in ipairs(World.get_exits(state.current_room)) do
        table.insert(out, "  " .. World.rooms[exit].name)
    end
    table.insert(out, "Evidence:")
    -- sort filenames for stable display
    local items = World.get_items_in_room(state.current_room)
    local fnames = {}
    for _, item in ipairs(items) do
        table.insert(fnames, item.filename)
    end
    table.sort(fnames)
    if #fnames == 0 then
        table.insert(out, "  (nothing of note)")
    else
        for _, fname in ipairs(fnames) do
            table.insert(out, "  " .. fname)
        end
    end
    return table.concat(out, "\n")
end

function handlers.cd(state, args)
    -- Strip -L / -P / -e flags: no symlinks in the mansion, all are no-ops.
    local filtered = {}
    for _, a in ipairs(args) do
        if a ~= "-L" and a ~= "-P" and a ~= "-e" then
            table.insert(filtered, a)
        end
    end
    args = filtered

    -- Derive root once: the room with no parent.
    local root_id = "foyer"
    for id, r in pairs(World.rooms) do
        if not r.parent then root_id = id; break end
    end

    -- cd with no args (or flags only): go to root (~)
    if #args == 0 then
        if state.current_room == root_id then
            return "You are already in the " .. World.rooms[root_id].name .. "."
        end
        state.previous_room = state.current_room
        state.current_room  = root_id
        state.visited[root_id] = true
        World.check_unlocks(state)
        return World.rooms[root_id].description
    end

    local function get_parent(room_id)
        return World.rooms[room_id].parent or room_id  -- stay put at root
    end

    local function find_adjacent(from_id, name)
        local name_lower = name:lower()
        for _, exit in ipairs(World.get_exits(from_id)) do
            local r = World.rooms[exit]
            if r.id == name_lower or r.name:lower() == name_lower then
                return exit
            end
        end
        return nil
    end

    -- Split path on "/" and trim each component.
    local path = table.concat(args, " ")
    local components = {}
    for part in path:gmatch("[^/]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(components, trimmed)
        end
    end

    -- Walk components left-to-right from current room.
    -- .  → stay   ..  → parent (Foyer)   ~ → Foyer   name → adjacent room
    local cursor = state.current_room
    local traversed = {}

    for _, comp in ipairs(components) do
        if comp == "." then
            -- stay put; no-op like in bash
        elseif comp == "-" then
            -- cd - swaps to previous room, like bash
            local prev = state.previous_room
            if prev == state.current_room then
                return "You have not moved yet."
            end
            state.previous_room = state.current_room
            state.current_room  = prev
            state.visited[prev] = true
            World.check_unlocks(state)
            return room_path(prev) .. "\n" .. World.rooms[prev].description
        elseif comp == ".." then
            local parent = get_parent(cursor)
            if parent ~= cursor then
                cursor = parent
                table.insert(traversed, cursor)
            end
            -- silently stay at root when already there, matching bash at /
        elseif comp == "~" then
            if cursor ~= root_id then
                cursor = root_id
                table.insert(traversed, cursor)
            end
        else
            local next_id = find_adjacent(cursor, comp)
            if not next_id then
                local comp_lower = comp:lower()
                for id, r in pairs(World.rooms) do
                    if id == comp_lower or r.name:lower() == comp_lower then
                        return "There is no direct path to the " .. r.name
                            .. " from the " .. World.rooms[cursor].name .. "."
                    end
                end
                return "There is no such place as \"" .. comp
                    .. "\" in the mansion. Try `ls` for exits."
            end
            cursor = next_id
            table.insert(traversed, cursor)
        end
    end

    if cursor == state.current_room then
        return "You are already here."
    end

    for _, room_id in ipairs(traversed) do
        state.visited[room_id] = true
    end
    state.previous_room = state.current_room
    state.current_room  = cursor
    World.check_unlocks(state)
    return World.rooms[cursor].description
end

function handlers.pwd(state, _)
    return room_path(state.current_room)
        .. "  (" .. World.rooms[state.current_room].name .. ")"
end

function handlers.cwd(state, _)
    local prev = state.previous_room
    if prev == state.current_room then
        return "(no previous room — you have not moved yet)"
    end
    return room_path(prev)
        .. "  (" .. World.rooms[prev].name .. ")"
end

function handlers.exit(_, _)
    love.event.quit()
    return ""
end

function handlers.echo(_, args)
    return table.concat(args, " ")
end

function handlers.cat(state, args)
    if #args == 0 then
        return "Usage: cat <file>     (try `ls` to see what is in this room)"
    end
    local fname = args[1]
    local item = World.get_item(state.current_room, fname)
    if item then
        state.files_read[state.current_room .. "/" .. fname] = true
        World.check_unlocks(state)
        state.popup_item = item
        return item.content
    end
    -- friendly redirect if the file exists in another visited room
    for room_id, _ in pairs(state.visited) do
        if World.get_item(room_id, fname) then
            return "That document is in the " .. World.rooms[room_id].name
                .. ", not here."
        end
    end
    return "There is nothing here by that name."
end

function handlers.grep(state, args)
    if #args == 0 then
        return "Usage: grep <pattern> <file>\n       grep -r <pattern>"
    end

    local recursive = false
    local idx = 1
    if args[1] == "-r" or args[1] == "-R" then
        recursive = true
        idx = 2
    end

    local pattern = args[idx]
    if not pattern or pattern == "" then
        return "Usage: grep <pattern> <file>\n       grep -r <pattern>"
    end
    local fname = args[idx + 1]
    local needle = pattern:lower()

    local results = {}

    local function search_one(room_id, file_name, content)
        for line in (content .. "\n"):gmatch("([^\n]*)\n") do
            if line:lower():find(needle, 1, true) then
                if recursive then
                    table.insert(results,
                        World.rooms[room_id].name .. "/" .. file_name
                        .. ":  " .. line)
                else
                    table.insert(results, line)
                end
            end
        end
    end

    if recursive then
        -- stable iteration order: rooms then filenames
        local room_ids = {}
        for id, _ in pairs(state.visited) do
            table.insert(room_ids, id)
        end
        table.sort(room_ids)
        for _, room_id in ipairs(room_ids) do
            local items = World.get_items_in_room(room_id)
            local sorted = {}
            for _, it in ipairs(items) do
                table.insert(sorted, it)
            end
            table.sort(sorted, function(a, b) return a.filename < b.filename end)
            for _, it in ipairs(sorted) do
                search_one(room_id, it.filename, it.content)
            end
        end
    else
        if not fname then
            return "Usage: grep <pattern> <file>\n       grep -r <pattern>"
        end
        local item = World.get_item(state.current_room, fname)
        if not item then
            return "There is nothing here by that name."
        end
        search_one(state.current_room, fname, item.content)
    end

    if #results == 0 then
        return "(no matches)"
    end
    return table.concat(results, "\n")
end

function handlers.accuse(state, args)
    if #args == 0 then
        return "Usage: accuse <name>\n"
            .. "You must name one of the four guests."
    end
    local input = table.concat(args, " ")
        :lower():gsub("^%s+", ""):gsub("%s+$", "")
    local resolved = World.accuse_aliases[input]
    if not resolved then
        return "You glance around the drawing room. No one there\n"
            .. "answers to that name. Try a surname, or a full name."
    end

    if resolved == World.murderer then
        state.won = true
        state.win_time = state.elapsed
        state.win_commands = state.command_count
        return "You point your finger across the drawing room at\n"
            .. "Dr. Reginald Croft.\n\n"
            .. "His face goes white. His hand drifts toward his coat\n"
            .. "pocket, then stops. He sits — very slowly — upon the\n"
            .. "chaise, and the fight goes out of him.\n\n"
            .. "  \"I never meant... I never meant for it to come to\n"
            .. "   this. He was going to ruin me.\"\n\n"
            .. "He confesses to all of it: the embezzlement from the\n"
            .. "village medical fund, the lethal dose, the gloves he\n"
            .. "wore to handle the bottle, the one he panicked and\n"
            .. "hid in the cellar before the body had even gone cold.\n\n"
            .. "The case is yours."
    end

    return "You point your finger at " .. resolved .. ".\n\n"
        .. "They blanch, sputter, and then their eyes go cold:\n"
        .. "  \"You have no proof — and you are wrong.\"\n\n"
        .. "The room is silent. The real killer relaxes, just a little.\n"
        .. "(Keep looking. The truth is in the evidence.)"
end

-- ---------- public entry point ----------

function M.execute(state, input)
    input = input:gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return "" end

    if state.start_time == nil then
        state.start_time = love.timer.getTime()
    end
    state.command_count = state.command_count + 1

    local tokens = tokenize(input)
    local cmd = tokens[1]:lower()
    local args = {}
    for i = 2, #tokens do args[i - 1] = tokens[i] end

    local handler = handlers[cmd]
    if not handler then
        -- friendly, in-world feedback for unknown commands
        return "You mutter the word \"" .. cmd .. "\" under your breath.\n"
            .. "Nothing in the house responds. (Type `help` for what you\n"
            .. "can actually do.)"
    end

    if not state.unlocked[cmd] then
        return locked_message(cmd)
    end

    return handler(state, args) or ""
end

return M
