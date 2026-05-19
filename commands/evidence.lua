-- evidence.lua — cat, grep

local World = require("world")

local function cat(state, args)
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
    for room_id, _ in pairs(state.visited) do
        if World.get_item(room_id, fname) then
            return "That document is in the " .. World.rooms[room_id].name
                .. ", not here."
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
                if lc == "r" then flags.r = true
                elseif lc == "v" then flags.v = true
                elseif lc == "n" then flags.n = true
                elseif lc == "l" then flags.l = true
                elseif lc == "a" then flags.a = true
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

    local function match(line)
        local hit = line:lower():find(needle, 1, true) ~= nil
        return flags.v and not hit or (not flags.v and hit)
    end

    local function search_one(room_id, item, line_prefix)
        local linenum = 0
        for line in (item.content .. "\n"):gmatch("([^\n]*)\n") do
            linenum = linenum + 1
            if match(line) then
                local prefix = line_prefix
                if flags.n then prefix = prefix .. linenum .. ": " end
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
                if (glob_visible and not is_hidden)
                or (glob_hidden  and is_hidden)
                or (not glob_visible and not glob_hidden) then
                    table.insert(out, it)
                end
            end
            return out
        end
        return all
    end

    if flags.r then
        local room_ids = {}
        for id in pairs(state.visited) do table.insert(room_ids, id) end
        table.sort(room_ids)
        for _, room_id in ipairs(room_ids) do
            local items = items_for_room(room_id)
            table.sort(items, function(a, b) return a.filename < b.filename end)
            for _, it in ipairs(items) do
                if flags.l then
                    local label = World.rooms[room_id].name .. "/" .. it.filename
                    for line in (it.content .. "\n"):gmatch("([^\n]*)\n") do
                        if match(line) then table.insert(results, label); break end
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
            table.sort(items, function(a, b) return a.filename < b.filename end)
            for _, it in ipairs(items) do
                if flags.l then
                    for line in (it.content .. "\n"):gmatch("([^\n]*)\n") do
                        if match(line) then table.insert(results, it.filename); break end
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
                local include_hidden = flags.a or fname:sub(1, 1) == "."
                local item = World.get_item(state.current_room, fname, include_hidden)
                if not item then
                    return "There is nothing here by that name."
                end
                if flags.l then
                    for line in (item.content .. "\n"):gmatch("([^\n]*)\n") do
                        if match(line) then table.insert(results, fname); break end
                    end
                else
                    search_one(state.current_room, item, "")
                end
            end
        end
    end

    if #results == 0 then return "(no matches)" end
    return table.concat(results, "\n")
end

return { cat = cat, grep = grep }
