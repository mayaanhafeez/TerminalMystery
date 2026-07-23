-- navigation.lua — ls, cd, pwd, cwd

local World = require("world")
local Audio = require("audio")

local function room_path(room_id)
    local parts = {}
    local id = room_id
    while id do
        table.insert(parts, World.rooms[id].id)
        id = World.rooms[id].parent
    end
    local n = #parts
    for i = 1, math.floor(n / 2) do
        parts[i], parts[n - i + 1] = parts[n - i + 1], parts[i]
    end
    parts[1] = "~"
    if n == 1 then return "~" end
    return table.concat(parts, "/")
end

-- Resolve a slash-separated path from from_id without mutating state.
-- Returns target room id on success, or nil + error string on failure.
local function resolve_path(from_id, path_str, previous_room)
    local root_id
    for id, r in pairs(World.rooms) do
        if not r.parent then root_id = id; break end
    end

    local function find_adjacent(cursor, name)
        local name_lower = name:lower()
        for _, exit in ipairs(World.get_exits(cursor)) do
            local r = World.rooms[exit]
            if r.id == name_lower or r.name:lower() == name_lower then
                return exit
            end
        end
        return nil
    end

    local components = {}
    for part in path_str:gmatch("[^/]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then table.insert(components, trimmed) end
    end

    local cursor = from_id
    for _, comp in ipairs(components) do
        if comp == "." then
            -- no-op
        elseif comp == "-" then
            cursor = previous_room or cursor
        elseif comp == ".." then
            cursor = World.rooms[cursor].parent or cursor
        elseif comp == "~" then
            cursor = root_id
        else
            local next_id = find_adjacent(cursor, comp)
            if not next_id then
                local comp_lower = comp:lower()
                for id, r in pairs(World.rooms) do
                    if id == comp_lower or r.name:lower() == comp_lower then
                        return nil, "no direct path to " .. r.name
                            .. " from " .. World.rooms[cursor].name
                    end
                end
                return nil, comp .. ": No such directory"
            end
            cursor = next_id
        end
    end
    return cursor
end

local function ls(state, args)
    local show_hidden = false
    local path_parts = {}

    for _, a in ipairs(args) do
        if a == "-a" then
            show_hidden = true
        elseif a:sub(1, 1) == "-" then
            return "ls: " .. a .. ": invalid option\nusage: ls [-a] [path]"
        else
            table.insert(path_parts, a)
        end
    end

    local target_id = state.current_room
    if #path_parts > 0 then
        -- join with "/" so "ls .. study" and "ls ../study" both work
        local path_str = table.concat(path_parts, "/")
        local resolved, err = resolve_path(state.current_room, path_str, state.previous_room)
        if not resolved then
            return "ls: " .. err
        end
        target_id = resolved
    end

    local room = World.rooms[target_id]
    local out = {}
    table.insert(out, "-- " .. room.name .. " --")
    table.insert(out, "Exits:")
    for _, exit in ipairs(World.get_exits(target_id)) do
        local r = World.rooms[exit]
        if show_hidden or not r.hidden then
            table.insert(out, "  " .. r.name)
        end
    end
    table.insert(out, "Evidence:")
    local items = World.get_items_in_room(target_id, show_hidden)
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

local function cd(state, args)
    local filtered = {}
    for _, a in ipairs(args) do
        if a ~= "-L" and a ~= "-P" and a ~= "-e" then
            table.insert(filtered, a)
        end
    end
    args = filtered

    local root_id = "foyer"
    for id, r in pairs(World.rooms) do
        if not r.parent then root_id = id; break end
    end

    if #args == 0 then
        if state.current_room == root_id then
            return "You are already in the " .. World.rooms[root_id].name .. "."
        end
        local was_new = not state.visited[root_id]
        state.previous_room = state.current_room
        state.current_room  = root_id
        state.visited[root_id] = true
        World.check_unlocks(state)
        Audio.set_room(root_id)
        Audio.play(was_new and "door_new" or "step")
        Audio.play_delayed("step", 0.2) -- second footfall: you walk into the room
        return World.rooms[root_id].description
    end

    local function get_parent(room_id)
        return World.rooms[room_id].parent or room_id
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

    local path = table.concat(args, " ")
    local components = {}
    for part in path:gmatch("[^/]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then table.insert(components, trimmed) end
    end

    local cursor = state.current_room
    local traversed = {}
    local badge_used = false

    for _, comp in ipairs(components) do
        if comp == "." then
            -- no-op
        elseif comp == "-" then
            local prev = state.previous_room
            if prev == state.current_room then
                return "You have not moved yet."
            end
            state.previous_room = state.current_room
            state.current_room  = prev
            state.visited[prev] = true
            World.check_unlocks(state)
            Audio.set_room(prev)
            Audio.play("step")
            Audio.play_delayed("step", 0.19)
            return room_path(prev) .. "\n" .. World.rooms[prev].description
        elseif comp == ".." then
            local parent = get_parent(cursor)
            if parent ~= cursor then
                cursor = parent
                table.insert(traversed, cursor)
            end
        elseif comp == "~" then
            if cursor ~= root_id then
                cursor = root_id
                table.insert(traversed, cursor)
            end
        else
            local next_id = find_adjacent(cursor, comp)
            if not next_id then
                local comp_lower = comp:lower()
                for _, r in pairs(World.rooms) do
                    if r.id == comp_lower or r.name:lower() == comp_lower then
                        return "There is no direct path to the " .. r.name
                            .. " from the " .. World.rooms[cursor].name .. "."
                    end
                end
                return comp .. ": No such directory"
            end
            local dest = World.rooms[next_id]
            if dest.mode == "000" then
                Audio.play("locked")
                return "Permission denied. The " .. dest.name .. " is locked."
            end
            if dest.requires then
                -- The key must be in the room you are leaving *from* (cursor),
                -- so you can `mv`/`cp` it there first to open the door.
                local key_present = false
                for _, it in ipairs(World.get_items_in_room(cursor, true)) do
                    if it.filename == dest.requires or it.id == dest.requires then
                        key_present = true
                        break
                    end
                end
                if not key_present then
                    Audio.play("locked")
                    return "The smart lock blinks red. You need a badge to enter the "
                        .. dest.name .. "."
                end
                badge_used = true
            end
            cursor = next_id
            table.insert(traversed, cursor)
        end
    end

    if cursor == state.current_room then
        return "You are already here."
    end

    local was_new = not state.visited[cursor]
    for _, room_id in ipairs(traversed) do
        state.visited[room_id] = true
    end
    state.previous_room = state.current_room
    state.current_room  = cursor
    World.check_unlocks(state)
    Audio.set_room(cursor)
    if badge_used then
        Audio.play("badge_ok")
    elseif was_new then
        Audio.play("door_new")
    else
        Audio.play("step")
    end
    Audio.play_delayed("step", 0.2) -- second footfall: you walk into the room
    return World.rooms[cursor].description
end

local function pwd(state, _)
    return room_path(state.current_room)
end

local function cwd(state, _)
    local prev = state.previous_room
    if prev == state.current_room then
        return "(no previous room — you have not moved yet)"
    end
    return room_path(prev)
end

return { ls = ls, cd = cd, pwd = pwd, cwd = cwd }
