-- navigation.lua — ls, cd, pwd, cwd

local World = require("world")

local function room_path(room_id)
    local parts = {}
    local id = room_id
    while id do
        local room = World.rooms[id]
        table.insert(parts, 1, room.id)
        id = room.parent
    end
    parts[1] = "~"
    if #parts == 1 then return "~" end
    return table.concat(parts, "/")
end

local function ls(state, args)
    local show_hidden = args[1] == "-a"
    local room = World.rooms[state.current_room]
    local out = {}
    table.insert(out, "-- " .. room.name .. " --")
    table.insert(out, "Exits:")
    for _, exit in ipairs(World.get_exits(state.current_room)) do
        if not World.rooms[exit].hidden then
            table.insert(out, "  " .. World.rooms[exit].name)
        end
    end
    table.insert(out, "Evidence:")
    local items = World.get_items_in_room(state.current_room, show_hidden)
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
        state.previous_room = state.current_room
        state.current_room  = root_id
        state.visited[root_id] = true
        World.check_unlocks(state)
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

local function pwd(state, _)
    return room_path(state.current_room)
        .. "  (" .. World.rooms[state.current_room].name .. ")"
end

local function cwd(state, _)
    local prev = state.previous_room
    if prev == state.current_room then
        return "(no previous room — you have not moved yet)"
    end
    return room_path(prev)
        .. "  (" .. World.rooms[prev].name .. ")"
end

return { ls = ls, cd = cd, pwd = pwd, cwd = cwd }
