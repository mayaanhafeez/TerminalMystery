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
    if not item then return "mv: " .. src_path .. ": no such file" end

    local dst_id, resolve_err = World.resolve_room_path(state.current_room, dst_arg)
    if resolve_err then return "mv: " .. resolve_err end
    if not state.visited[dst_id] then
        return "mv: " .. dst_arg .. ": no such visited room"
    end
    if dst_id == src_room_id then
        return "mv: source and destination are the same room"
    end

    World.rooms[src_room_id].items[src_fname] = nil
    World.rooms[dst_id].items[src_fname] = item
    item.room = dst_id
    return "Moved " .. src_fname .. " to " .. World.rooms[dst_id].name .. "."
end

local function cp(state, args)
    if #args < 2 then
        return "Usage: cp <file> <room>"
    end
    local fname       = args[1]
    local target_name = table.concat(args, " ", 2)

    local item = World.get_item(state.current_room, fname)
    if not item then return "cp: " .. fname .. ": no such file in this room" end

    local target_id, resolve_err = World.resolve_room_path(state.current_room, target_name)
    if resolve_err then return "cp: " .. resolve_err end
    if not state.visited[target_id] then
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
    copy.id     = item.id .. "_copy_" .. target_id
    copy.room   = target_id
    copy.copied = true
    World.rooms[target_id].items[copy.filename] = copy
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
    if not fname then return "Usage: rm -f <file>" end

    local item = World.get_item(state.current_room, fname)
    if not item then return "rm: " .. fname .. ": no such file" end
    if not force then
        return "This cannot be undone. Run `rm -f " .. fname
            .. "` to permanently destroy this evidence."
    end

    World.rooms[state.current_room].items[fname] = nil
    if not state.destroyed then state.destroyed = {} end
    state.destroyed[state.current_room .. "/" .. fname] = true
    return "rm: " .. fname .. " destroyed."
end

-- Interpret a chmod mode as a write permission for a FILE.
-- Returns true (writable), false (read-only), or nil (mode says nothing about write).
local function mode_writable(mode)
    if mode == "+w" or mode == "u+w" then return true end
    if mode == "-w" or mode == "u-w" then return false end
    if mode:match("^%d%d?%d?$") then
        return (tonumber(mode:sub(1, 1)) % 4) >= 2  -- owner write bit (value 2)
    end
    if mode:match("^[r%-][w%-][x%-]$") then          -- symbolic, e.g. rw- / r--
        return mode:sub(2, 2) == "w"
    end
    return nil
end

local function chmod(state, args)
    if #args < 2 then
        return "Usage: chmod <mode> <room|file>\n"
            .. "Rooms: chmod 000 cellar (lock)   Files: chmod +w notes.txt (writable)"
    end
    local mode        = args[1]
    local target_name = table.concat(args, " ", 2)
    local name_lower  = target_name:lower()
    for id, room in pairs(World.rooms) do
        if id == name_lower or room.name:lower() == name_lower then
            room.mode = mode
            return "chmod: " .. room.name .. " \xe2\x86\x92 " .. mode
        end
    end
    local item = World.get_item(state.current_room, target_name)
    if item then
        item.mode = mode
        local w = mode_writable(mode)
        if w ~= nil then
            item.writable = w
        end
        local perm = item.writable and "rw-" or "r--"
        return "chmod: " .. item.filename .. " \xe2\x86\x92 " .. perm
    end
    return "chmod: " .. target_name .. ": no such file or room"
end

return { mv = mv, cp = cp, rm = rm, chmod = chmod }
