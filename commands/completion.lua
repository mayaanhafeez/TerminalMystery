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

    -- File completion — supports "Room/file" cross-room paths.
    local function complete_file()
        local result, seen = {}, {}
        if partial:find("/", 1, true) then
            local room_part, file_part = partial:match("^([^/]*)/(.*)$")
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
                        table.insert(result, before .. prefix .. "/" .. item.filename .. " ")
                        seen[item.filename] = true
                    end
                end
            end
        else
            for _, item in ipairs(World.get_items_in_room(state.current_room, false)) do
                if not seen[item.filename] and matches(item.filename) then
                    table.insert(result, before .. item.filename .. " ")
                    seen[item.filename] = true
                end
            end
            for room_id, room in pairs(World.rooms) do
                if state.visited[room_id] and room_id ~= state.current_room
                    and not room.hidden and matches(room.name)
                    and #World.get_items_in_room(room_id, false) > 0 then
                    table.insert(result, before .. room.name .. "/")
                end
            end
        end
        return result
    end

    -- Room completion for mv/cp destinations — supports "../Room" paths.
    local function complete_room()
        local result = {}
        if partial:find("/", 1, true) then
            local path_so_far, in_progress = partial:match("^(.*)/(.*)$")
            local cursor = resolve_prefix(path_so_far)
            local ip_lower = in_progress:lower()
            for id, room in pairs(World.rooms) do
                if state.visited[id] and not room.hidden
                    and room.name:lower():sub(1, #ip_lower) == ip_lower then
                    table.insert(result, before .. path_so_far .. "/" .. room.name .. " ")
                end
            end
        else
            if #partial > 0 and ("../"):sub(1, #partial) == partial then
                table.insert(result, before .. "../")
            end
            if ("./"):sub(1, #partial) == partial then
                table.insert(result, before .. "./ ")
            end
            for room_id, room in pairs(World.rooms) do
                if state.visited[room_id] and not room.hidden and matches(room.name) then
                    table.insert(result, before .. room.name .. " ")
                end
            end
        end
        return result
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
        local result, seen = {}, {}
        if partial:find("/", 1, true) then
            -- Resolve everything before the last slash, then show exits of that room
            local path_so_far, in_progress = partial:match("^(.*)/(.*)$")
            local cursor = resolve_prefix(path_so_far)
            local ip_lower = in_progress:lower()
            for _, exit_id in ipairs(World.get_exits(cursor)) do
                local room = World.rooms[exit_id]
                if not room.hidden and not seen[room.name]
                    and room.name:lower():sub(1, #ip_lower) == ip_lower then
                    table.insert(result, before .. path_so_far .. "/" .. room.name .. "/")
                    seen[room.name] = true
                end
            end
        else
            if #partial > 0 and ("../"):sub(1, #partial) == partial then
                table.insert(result, before .. "../")
            end
            local exits = World.get_exits(state.current_room)
            for _, exit_id in ipairs(exits) do
                local room = World.rooms[exit_id]
                if not room.hidden and not seen[room.name] and matches(room.name) then
                    table.insert(result, before .. room.name .. "/")
                    seen[room.name] = true
                end
            end
        end
        return result

    elseif cmd == "cat" or cmd == "rm" then
        return complete_file()

    elseif cmd == "sed" then
        -- Only offer file names once the s/// script has been typed (2nd non-flag arg).
        if non_flags >= 1 and not (has_trailing_space and non_flags == 0) then
            return complete_file()
        end
        return {}

    elseif cmd == "grep" then
        if has_trailing_space and non_flags == 0 then return {} end
        if not has_trailing_space and non_flags <= 1 then return {} end
        return complete_file()

    elseif cmd == "mv" or cmd == "cp" then
        local on_src = (has_trailing_space and non_flags == 0)
            or (not has_trailing_space and non_flags == 1)
        local on_dst = (has_trailing_space and non_flags == 1)
            or (not has_trailing_space and non_flags == 2)
        if on_src then return complete_file() end
        if on_dst then return complete_room() end

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
