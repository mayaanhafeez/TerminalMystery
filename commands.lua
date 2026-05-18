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

-- ---------- handlers ----------

function handlers.help(state, _)
    local lines = {
        "Available commands:",
        "  ls                       list the contents of this room",
        "  cd <room>                move to an adjacent room",
        "  cd                       show the exits from this room",
        "  echo <text>              repeat text back",
        "  help                     show this list",
        "  accuse <name>            name the murderer",
    }
    if state.unlocked.cat then
        table.insert(lines, "  cat <file>               read a piece of evidence")
    else
        table.insert(lines, "  cat <file>               (not yet — investigate first)")
    end
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
    for _, exit in ipairs(room.exits) do
        table.insert(out, "  " .. World.rooms[exit].name)
    end
    table.insert(out, "Evidence:")
    -- sort filenames for stable display
    local fnames = {}
    for fname, _ in pairs(room.files) do
        table.insert(fnames, fname)
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
    local room = World.rooms[state.current_room]
    if #args == 0 then
        local out = { "Exits from " .. room.name .. ":" }
        for _, exit in ipairs(room.exits) do
            table.insert(out, "  " .. World.rooms[exit].name)
        end
        return table.concat(out, "\n")
    end

    -- allow "cd .." as a convenience: return to the previous room
    if args[1] == ".." then
        if state.previous_room == state.current_room then
            return "You are already where you began."
        end
        local prev = state.previous_room
        state.previous_room = state.current_room
        state.current_room  = prev
        state.visited[prev] = true
        World.check_unlocks(state)
        return World.rooms[prev].description
    end

    local target_input = table.concat(args, " "):lower()
    local target_id

    -- adjacent rooms only
    for _, exit in ipairs(room.exits) do
        local r = World.rooms[exit]
        if r.id == target_input or r.name:lower() == target_input then
            target_id = exit
            break
        end
    end

    if not target_id then
        -- helpful message if the player named a real room that isn't adjacent
        for id, r in pairs(World.rooms) do
            if id == target_input or r.name:lower() == target_input then
                return "There is no direct path to the " .. r.name
                    .. " from here.\nReturn through the Foyer first."
            end
        end
        return "There is no such place in the mansion. Try `cd` for the exits."
    end

    state.previous_room = state.current_room
    state.current_room  = target_id
    state.visited[target_id] = true
    World.check_unlocks(state)
    return World.rooms[target_id].description
end

function handlers.echo(_, args)
    return table.concat(args, " ")
end

function handlers.cat(state, args)
    if #args == 0 then
        return "Usage: cat <file>     (try `ls` to see what is in this room)"
    end
    local fname = args[1]
    local room = World.rooms[state.current_room]
    local content = room.files[fname]
    if content then
        state.files_read[state.current_room .. "/" .. fname] = true
        World.check_unlocks(state)
        return content
    end
    -- friendly redirect if the file exists in another visited room
    for room_id, _ in pairs(state.visited) do
        if World.rooms[room_id].files[fname] then
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
            local room = World.rooms[room_id]
            local fnames = {}
            for fn, _ in pairs(room.files) do
                table.insert(fnames, fn)
            end
            table.sort(fnames)
            for _, fn in ipairs(fnames) do
                search_one(room_id, fn, room.files[fn])
            end
        end
    else
        if not fname then
            return "Usage: grep <pattern> <file>\n       grep -r <pattern>"
        end
        local room = World.rooms[state.current_room]
        local content = room.files[fname]
        if not content then
            return "There is nothing here by that name."
        end
        search_one(state.current_room, fname, content)
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
