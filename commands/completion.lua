-- commands/completion.lua — tab completion logic (no LÖVE dependency)

local World = require("world")
local M = {}

function M.get_completions(state, input)
    local has_trailing_space = input:match("%s$") ~= nil

    local tokens = {}
    for token in input:gmatch("%S+") do
        table.insert(tokens, token)
    end

    local partial, before
    if has_trailing_space then
        partial = ""
        before  = input
    elseif #tokens > 0 then
        partial = tokens[#tokens]
        before  = input:match("^(.*%s)%S+$") or ""
    else
        partial = ""
        before  = ""
    end
    local partial_lower = partial:lower()

    local function matches(candidate)
        return candidate:lower():sub(1, #partial_lower) == partial_lower
    end

    -- Walk a "/"-separated path from current_room and return the final room id.
    local function resolve_prefix(path_str)
        local cursor = state.current_room
        for seg in path_str:gmatch("[^/]+") do
            if seg == ".." then
                cursor = (World.rooms[cursor] and World.rooms[cursor].parent) or cursor
            elseif seg ~= "." then
                local seg_lower = seg:lower()
                for id, r in pairs(World.rooms) do
                    if id == seg_lower or r.name:lower() == seg_lower then
                        cursor = id; break
                    end
                end
            end
        end
        return cursor
    end

    -- File completion — supports "Room/file" cross-room paths. `part` is the
    -- in-progress path (may contain spaces, e.g. "The Den/vic") and `pre` is the
    -- already-typed text it should be appended to. Files end with a space,
    -- directories (rooms) end with "/".
    local function complete_file(part, pre)
        local result, seen = {}, {}
        if part:find("/", 1, true) then
            local room_part, file_part = part:match("^([^/]*)/(.*)$")
            local target_id
            if room_part == "." or room_part == "" then
                target_id = state.current_room
            else
                local rp_lower = room_part:lower()
                for id, r in pairs(World.rooms) do
                    if id == rp_lower or r.name:lower() == rp_lower then
                        target_id = id; break
                    end
                end
            end
            if target_id then
                local file_lower = file_part:lower()
                local prefix = (room_part == ".") and "." or World.rooms[target_id].name
                for _, item in ipairs(World.get_items_in_room(target_id, false)) do
                    if not seen[item.filename]
                        and item.filename:lower():sub(1, #file_lower) == file_lower then
                        table.insert(result, pre .. prefix .. "/" .. item.filename .. " ")
                        seen[item.filename] = true
                    end
                end
            end
        else
            local p_lower = part:lower()
            for _, item in ipairs(World.get_items_in_room(state.current_room, false)) do
                if not seen[item.filename]
                    and item.filename:lower():sub(1, #p_lower) == p_lower then
                    table.insert(result, pre .. item.filename .. " ")
                    seen[item.filename] = true
                end
            end
            for room_id, room in pairs(World.rooms) do
                if state.visited[room_id] and room_id ~= state.current_room
                    and not room.hidden and room.name:lower():sub(1, #p_lower) == p_lower
                    and #World.get_items_in_room(room_id, false) > 0 then
                    table.insert(result, pre .. room.name .. "/")
                end
            end
        end
        return result
    end

    -- Destination completion for mv/cp. A destination is a directory (room) or
    -- a "Room/newname" path. Directories get a trailing "/"; once a room is
    -- named ("Room/…"), we complete the file names inside it (trailing space).
    -- Relative room paths ("..", "../Room") still complete to rooms.
    local function complete_room(part, pre)
        local result, seen = {}, {}
        if part:find("/", 1, true) then
            local path_so_far, in_progress = part:match("^(.*)/(.*)$")
            local first = path_so_far:match("^([^/]*)") or ""
            if first == "." or first == ".." then
                -- Relative room navigation → complete reachable rooms.
                local cursor = resolve_prefix(path_so_far)
                local ip_lower = in_progress:lower()
                for id, room in pairs(World.rooms) do
                    if state.visited[id] and not room.hidden and not seen[room.name]
                        and room.name:lower():sub(1, #ip_lower) == ip_lower then
                        table.insert(result, pre .. path_so_far .. "/" .. room.name .. "/")
                        seen[room.name] = true
                    end
                end
            else
                -- "Room/name" → completing a file name inside Room. List the
                -- files already there (trailing space, they are files).
                local rp_lower = path_so_far:lower()
                local target_id
                for id, r in pairs(World.rooms) do
                    if id == rp_lower or r.name:lower() == rp_lower then
                        target_id = id; break
                    end
                end
                if target_id then
                    local ip_lower = in_progress:lower()
                    for _, item in ipairs(World.get_items_in_room(target_id, false)) do
                        if not seen[item.filename]
                            and item.filename:lower():sub(1, #ip_lower) == ip_lower then
                            table.insert(result,
                                pre .. path_so_far .. "/" .. item.filename .. " ")
                            seen[item.filename] = true
                        end
                    end
                end
            end
        else
            local pl = part:lower()
            if #part > 0 and ("../"):sub(1, #part) == part then
                table.insert(result, pre .. "../")
            end
            if ("./"):sub(1, #part) == part then
                table.insert(result, pre .. "./")
            end
            for room_id, room in pairs(World.rooms) do
                if state.visited[room_id] and not room.hidden
                    and room.name:lower():sub(1, #pl) == pl then
                    table.insert(result, pre .. room.name .. "/")
                end
            end
        end
        return result
    end

    -- Exit (room) completion for cd/ls — supports "../Room" and multi-word room
    -- names. Rooms always end with "/".
    local function complete_exits(part, pre)
        local result, seen = {}, {}
        if part:find("/", 1, true) then
            local path_so_far, in_progress = part:match("^(.*)/(.*)$")
            local cursor = resolve_prefix(path_so_far)
            local ip_lower = in_progress:lower()
            for _, exit_id in ipairs(World.get_exits(cursor)) do
                local room = World.rooms[exit_id]
                if not room.hidden and not seen[room.name]
                    and room.name:lower():sub(1, #ip_lower) == ip_lower then
                    table.insert(result, pre .. path_so_far .. "/" .. room.name .. "/")
                    seen[room.name] = true
                end
            end
        else
            local pl = part:lower()
            if #part > 0 and ("../"):sub(1, #part) == part then
                table.insert(result, pre .. "../")
            end
            for _, exit_id in ipairs(World.get_exits(state.current_room)) do
                local room = World.rooms[exit_id]
                if not room.hidden and not seen[room.name]
                    and room.name:lower():sub(1, #pl) == pl then
                    table.insert(result, pre .. room.name .. "/")
                    seen[room.name] = true
                end
            end
        end
        return result
    end

    -- The text of a single-path command's argument: everything after the
    -- command word, with any leading flag tokens (e.g. rm -f) folded into the
    -- prefix. Room names contain spaces, so we must not split on whitespace.
    -- Returns part (in-progress argument), pre (text it appends to), or nil.
    local function remainder()
        local head, rest = input:match("^(%S+%s+)(.*)$")
        if not head then return nil end
        while true do
            local flag, more = rest:match("^(%-%S+%s+)(.*)$")
            if flag then head = head .. flag; rest = more else break end
        end
        return rest, head
    end

    -- Command name completion
    if #tokens == 0 or (#tokens == 1 and not has_trailing_space) then
        local all_cmds = {
            "accuse", "cat", "cd", "chmod", "cp", "cwd", "diff",
            "echo", "exit", "find", "grep", "help", "ls", "mv", "pwd", "rm", "sed",
        }
        local result = {}
        for _, cmd in ipairs(all_cmds) do
            if matches(cmd) then table.insert(result, cmd .. " ") end
        end
        return result
    end

    local cmd = tokens[1]:lower()

    if partial:sub(1, 1) == "-" then return {} end  -- no flag completion

    local non_flags = 0
    for i = 2, #tokens do
        if tokens[i]:sub(1, 1) ~= "-" then non_flags = non_flags + 1 end
    end

    if cmd == "cd" or cmd == "ls" then
        local part, pre = remainder()
        if not part or part:sub(1, 1) == "-" then return {} end
        return complete_exits(part, pre)

    elseif cmd == "cat" or cmd == "rm" then
        local part, pre = remainder()
        if not part or part:sub(1, 1) == "-" then return {} end
        return complete_file(part, pre)

    elseif cmd == "sed" then
        -- Only offer file names once the s/// script has been typed (2nd non-flag arg).
        if non_flags >= 1 and not (has_trailing_space and non_flags == 0) then
            return complete_file(partial, before)
        end
        return {}

    elseif cmd == "grep" then
        if has_trailing_space and non_flags == 0 then return {} end
        if not has_trailing_space and non_flags <= 1 then return {} end
        return complete_file(partial, before)

    elseif cmd == "mv" or cmd == "cp" then
        -- Source is the first token after the command; the destination is
        -- everything after it (room names may contain spaces).
        local head, rest = input:match("^(%S+%s+)(.*)$")
        if not head then return {} end
        local src, sep, dst = rest:match("^(%S+)(%s+)(.*)$")
        if src then
            return complete_room(dst, head .. src .. sep)
        elseif rest:sub(1, 1) ~= "-" then
            return complete_file(rest, head)
        end
        return {}

    elseif cmd == "accuse" then
        local after_cmd   = input:match("^%S+%s+(.*)$") or ""
        local after_lower = after_cmd:lower()
        local result = {}
        for _, suspect in ipairs(World.suspects) do
            if suspect:lower():sub(1, #after_lower) == after_lower then
                table.insert(result, "accuse " .. suspect)
            end
        end
        return result
    end

    return {}
end

return M
