-- items.lua — mv, cp, rm, chmod

local World = require("world")
local Audio = require("audio")

-- Cap the length of a user-chosen filename (via `cp <file> <newname>`). Keeps
-- labels from overrunning their sprite in the room view; the longest built-in
-- evidence name is ~21 chars, so this leaves a little headroom.
local MAX_FILENAME_LEN = 24

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
    -- Re-place so the moved sprite doesn't land on an item already in the room.
    item.x, item.y = World.find_free_position(dst_id, src_fname)
    Audio.play("move")
    return "Moved " .. src_fname .. " to " .. World.rooms[dst_id].name .. "."
end

local function cp(state, args)
    if #args < 2 then
        return "Usage: cp <file> <destination>  (destination may be a room, a new"
            .. " name, or room/name)"
    end
    local src_path = args[1]
    local dst_arg  = table.concat(args, " ", 2)

    -- Resolve the source file (may be room/file).
    local src_room_id, src_fname, err = World.resolve_file_path(state.current_room, src_path)
    if err then return "cp: " .. err end
    if not src_fname then return "cp: " .. src_path .. ": is a directory" end

    local item = World.get_item(src_room_id, src_fname)
    if not item then return "cp: " .. src_path .. ": no such file" end

    -- Determine destination room + filename, matching real `cp`:
    --   * if the destination is a directory (room), copy into it under the
    --     source's name;
    --   * otherwise treat it as a target path/name (bare name → current room).
    local dst_room_id, dst_fname
    local as_room = World.resolve_room_path(state.current_room, dst_arg)
    if as_room then
        dst_room_id = as_room
        dst_fname   = src_fname
    else
        local rid, fname, ferr = World.resolve_file_path(state.current_room, dst_arg)
        if ferr then return "cp: " .. ferr end
        dst_room_id = rid
        dst_fname   = fname or src_fname
    end

    if #dst_fname > MAX_FILENAME_LEN then
        return "cp: " .. dst_fname .. ": name too long (max "
            .. MAX_FILENAME_LEN .. " characters)"
    end
    if not state.visited[dst_room_id] then
        return "cp: " .. dst_arg .. ": no such visited room"
    end
    if dst_room_id == src_room_id and dst_fname == src_fname then
        return "cp: '" .. src_fname .. "' and '" .. dst_fname .. "' are the same file"
    end
    if World.get_item(dst_room_id, dst_fname) then
        return "cp: " .. dst_fname .. " already exists in " .. World.rooms[dst_room_id].name
    end

    local copy = {}
    for k, v in pairs(item) do copy[k] = v end
    -- Keep the original registry id so the copy rehydrates its content from
    -- items.lua on load; uniqueness within a room is by filename.
    copy.id       = item.id
    copy.filename = dst_fname
    copy.room     = dst_room_id
    copy.copied   = true
    -- Randomize the copy's spot so it doesn't land on top of another sprite
    -- (the source it was copied from, or anything already in the destination).
    copy.x, copy.y = World.find_free_position(dst_room_id, dst_fname)
    World.rooms[dst_room_id].items[dst_fname] = copy
    Audio.play("move")

    if dst_room_id == src_room_id then
        return "Copied " .. src_fname .. " to " .. dst_fname .. "."
    end
    return "Copied " .. src_fname .. " to " .. World.rooms[dst_room_id].name
        .. (dst_fname ~= src_fname and ("/" .. dst_fname) or "") .. "."
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
        Audio.play("warn")
        return "This cannot be undone. Run `rm -f " .. fname
            .. "` to permanently destroy this evidence."
    end

    World.rooms[state.current_room].items[fname] = nil
    if not state.destroyed then state.destroyed = {} end
    state.destroyed[state.current_room .. "/" .. fname] = true
    Audio.play("destroy")
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
            -- Keypad-locked rooms only accept the exact code (case-insensitive).
            if room.lock_code and mode:lower() ~= room.lock_code:lower() then
                Audio.play("unlock_fail")
                return "chmod: " .. room.name .. ": incorrect code. The door stays locked."
            end
            room.mode = mode
            if room.lock_code then
                Audio.play("unlock_heavy")
            end
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
