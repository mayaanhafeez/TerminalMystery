-- items.lua — mv, cp, rm, chmod

local World = require("world")

local function mv(state, args)
    if #args < 2 then
        return "Usage: mv <source> <destination>  (source may be room/file)"
    end
    local src_path = args[1]
    local dst_arg  = table.concat(args, " ", 2)

    local src_room_id, src_fname, err = World.resolve_file_path(state.current_room, src_path)
    if err then return "mv: " .. err end
    if not src_fname then return "mv: " .. src_path .. ": is a directory" end

    local item = World.get_item(src_room_id, src_fname)
    if not item then
        return "mv: " .. src_path .. ": no such file"
    end

    -- Resolve destination: room name, ".", or "./room" style
    local dst_id
    local dst_lower = dst_arg:lower()
    if dst_arg == "." or dst_arg == "./" then
        dst_id = state.current_room
    else
        for id, room in pairs(World.rooms) do
            if (id == dst_lower or room.name:lower() == dst_lower) and state.visited[id] then
                dst_id = id; break
            end
        end
        -- Also accept "RoomName/" with trailing slash
        if not dst_id then
            local bare = dst_arg:match("^(.-)/?$")
            local bare_lower = bare:lower()
            for id, room in pairs(World.rooms) do
                if (id == bare_lower or room.name:lower() == bare_lower) and state.visited[id] then
                    dst_id = id; break
                end
            end
        end
    end

    if not dst_id then
        return "mv: " .. dst_arg .. ": no such visited room"
    end
    if dst_id == src_room_id then
        return "mv: source and destination are the same room"
    end
    item.room = dst_id
    return "Moved " .. src_fname .. " to " .. World.rooms[dst_id].name .. "."
end

local function cp(state, args)
    if #args < 2 then
        return "Usage: cp <file> <room>"
    end
    local fname = args[1]
    local target_name = table.concat(args, " ", 2)
    local item = World.get_item(state.current_room, fname)
    if not item then
        return "cp: " .. fname .. ": no such file in this room"
    end
    local name_lower = target_name:lower()
    local target_id = nil
    for id, room in pairs(World.rooms) do
        if (id == name_lower or room.name:lower() == name_lower) and state.visited[id] then
            target_id = id
            break
        end
    end
    if not target_id then
        return "cp: " .. target_name .. ": no such visited room"
    end
    if target_id == state.current_room then
        return "cp: source and destination are the same room"
    end
    if World.get_item(target_id, fname) then
        return "cp: " .. fname .. " already exists in " .. World.rooms[target_id].name
    end
    local copy = {}
    for k, v in pairs(item) do copy[k] = v end
    copy.room = target_id
    copy.copied = true
    copy.id = item.id .. "_copy_" .. target_id
    table.insert(World.items, copy)
    return "Copied " .. fname .. " to " .. World.rooms[target_id].name .. "."
end

local function rm(state, args)
    if #args == 0 then
        return "Usage: rm <file>  (use rm -f <file> to skip confirmation)"
    end
    local force = false
    local fname
    if args[1] == "-f" then
        force = true
        fname = args[2]
    else
        fname = args[1]
    end
    if not fname then
        return "Usage: rm -f <file>"
    end
    local item = World.get_item(state.current_room, fname)
    if not item then
        return "rm: " .. fname .. ": no such file"
    end
    if not force then
        return "This cannot be undone. Run `rm -f " .. fname
            .. "` to permanently destroy this evidence."
    end
    item.removed = true
    if not state.destroyed then state.destroyed = {} end
    state.destroyed[state.current_room .. "/" .. fname] = true
    return "rm: " .. fname .. " destroyed."
end

local function chmod(state, args)
    if #args < 2 then
        return "Usage: chmod <mode> <room|file>\n"
            .. "Example: chmod 000 cellar  or  chmod 755 cellar"
    end
    local mode = args[1]
    local target_name = table.concat(args, " ", 2)
    local name_lower = target_name:lower()
    for id, room in pairs(World.rooms) do
        if id == name_lower or room.name:lower() == name_lower then
            room.mode = mode
            return "chmod: " .. room.name .. " \xe2\x86\x92 " .. mode
        end
    end
    local item = World.get_item(state.current_room, target_name)
    if item then
        item.mode = mode
        return "chmod: " .. item.filename .. " \xe2\x86\x92 " .. mode
    end
    return "chmod: " .. target_name .. ": no such file or room"
end

return { mv = mv, cp = cp, rm = rm, chmod = chmod }
