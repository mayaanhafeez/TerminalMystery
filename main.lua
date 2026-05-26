-- main.lua
-- LÖVE callbacks, input handling, save-file I/O. The thin glue layer that
-- ties world.lua, commands.lua and render.lua together.

local utf8     = require("utf8")
local World    = require("world")
local Commands = require("commands")
local Render   = require("render")

local state           -- game state from World.new_state()
local term            -- terminal UI state (input/lines/scroll/history)
local best            -- personal best loaded from save (or nil)
local cursor_timer = 0

-- ---------- tab completion ----------

local function get_completions(state, input)
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

    -- Complete a file argument; supports "room/file" cross-room paths.
    -- When partial has no slash: shows current-room files + visited room names (with /)
    -- When partial has a slash:  shows files inside the named room
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
            -- Current-room files
            for _, item in ipairs(World.get_items_in_room(state.current_room, false)) do
                if not seen[item.filename] and matches(item.filename) then
                    table.insert(result, before .. item.filename .. " ")
                    seen[item.filename] = true
                end
            end
            -- Visited room name prefixes for cross-room access (e.g. "Library/")
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

    -- Complete a destination room (for mv/cp)
    local function complete_room()
        local result = {}
        if ("./"):sub(1, #partial) == partial then
            table.insert(result, before .. "./ ")
        end
        for room_id, room in pairs(World.rooms) do
            if state.visited[room_id] and not room.hidden and matches(room.name) then
                table.insert(result, before .. room.name .. " ")
            end
        end
        return result
    end

    -- Complete command name
    if #tokens == 0 or (#tokens == 1 and not has_trailing_space) then
        local all_cmds = {
            "accuse", "cat", "cd", "chmod", "cp", "cwd", "diff",
            "echo", "exit", "find", "grep", "help", "ls", "mv", "pwd", "rm",
        }
        local result = {}
        for _, cmd in ipairs(all_cmds) do
            if matches(cmd) then table.insert(result, cmd .. " ") end
        end
        return result
    end

    local cmd = tokens[1]:lower()

    if partial:sub(1, 1) == "-" then return {} end   -- no flag completion

    -- Count non-flag args after the command token
    local non_flags = 0
    for i = 2, #tokens do
        if tokens[i]:sub(1, 1) ~= "-" then non_flags = non_flags + 1 end
    end

    if cmd == "cd" or cmd == "ls" then
        local exits = World.get_exits(state.current_room)
        local result, seen = {}, {}
        for _, exit_id in ipairs(exits) do
            local room = World.rooms[exit_id]
            if not room.hidden then
                local name = room.name
                if not seen[name] and matches(name) then
                    table.insert(result, before .. name .. " ")
                    seen[name] = true
                end
            end
        end
        return result

    elseif cmd == "cat" or cmd == "rm" then
        return complete_file()

    elseif cmd == "grep" then
        -- Skip until the pattern arg has been typed (first non-flag token)
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

local INTRO = [[=== TERMINAL MYSTERY ===

It is the autumn of 1923. Lord Edmund Ashworth lies dead in his
Study at Ashworth Manor — a single drop of foam at the corner
of his mouth, a half-finished glass of brandy on the desk.

The constabulary is two hours away by motorcar. You are the
nearest investigator. The killer is still in the house.

You stand in the Foyer. Type `help` to see what you can do.
When you are certain, type `accuse <name>` to make your case.]]

-- ---------- save file ----------

local function load_best()
    if not love.filesystem.getInfo("scores.lua") then return nil end
    local content = love.filesystem.read("scores.lua")
    if not content then return nil end
    local chunk, err = load(content, "scores", "t", {})
    if not chunk then return nil end
    local ok, value = pcall(chunk)
    if ok and type(value) == "table"
        and type(value.best_time) == "number"
        and type(value.best_commands) == "number" then
        return value
    end
    return nil
end

local function save_best(b)
    local data = string.format(
        "return { best_time = %.6f, best_commands = %d }",
        b.best_time, b.best_commands)
    love.filesystem.write("scores.lua", data)
end

-- ---------- terminal helpers ----------

local function push_text(text, kind)
    kind = kind or "output"
    local wrapped = Render.wrap_text(text)
    for _, line in ipairs(wrapped) do
        table.insert(term.lines, { text = line, kind = kind })
    end
end

local function clear_tab_state()
    if not term or not term.tab_candidates then return end
    for i = #term.lines, 1, -1 do
        if term.lines[i].kind == "completion" then
            table.remove(term.lines, i)
        else
            break
        end
    end
    term.tab_candidates = nil
    term.tab_index      = nil
end

local function init_game()
    state = World.new_state()
    term = {
        lines          = {},
        input          = "",
        scroll         = 0,
        cursor_visible = true,
        history        = {},
        history_index  = nil,
        tab_candidates = nil,
        tab_index      = nil,
    }
    push_text(INTRO, "system")
    push_text("", "output")
    push_text(World.rooms.foyer.description, "output")
    push_text("", "output")
    best = load_best()
end

-- ---------- LÖVE callbacks ----------

function love.load()
    love.keyboard.setKeyRepeat(true)
    Render.load()
    init_game()
end

function love.update(dt)
    if state.start_time and not state.won then
        state.elapsed = love.timer.getTime() - state.start_time
    end
    cursor_timer = cursor_timer + dt
    if cursor_timer > 0.5 then
        cursor_timer = 0
        term.cursor_visible = not term.cursor_visible
    end
end

function love.draw()
    Render.draw(state, term, best)
end

local function on_win(result_text)
    push_text(result_text, "system")

    local prev_time = best and best.best_time
    local prev_cmds = best and best.best_commands

    state.new_time_record = (prev_time == nil) or (state.win_time     < prev_time)
    state.new_cmds_record = (prev_cmds == nil) or (state.win_commands < prev_cmds)

    best = {
        best_time     = math.min(prev_time or math.huge, state.win_time),
        best_commands = math.min(prev_cmds or math.huge, state.win_commands),
    }
    save_best(best)
end

local function execute_input()
    clear_tab_state()
    local input = term.input
    term.input          = ""
    term.scroll         = 0
    term.history_index  = nil

    if input == "" then
        push_text("> ", "input")
        return
    end

    table.insert(term.history, input)
    push_text("> " .. input, "input")

    local result = Commands.execute(state, input)
    if state.won then
        on_win(result or "")
    elseif result and result ~= "" then
        push_text(result, "output")
    end
    push_text("", "output")
end

function love.textinput(t)
    if state.popup_item then return end
    if state.won then return end
    if t == "\t" then return end  -- handled in keypressed
    clear_tab_state()
    term.input = term.input .. t
    cursor_timer = 0
    term.cursor_visible = true
end

function love.keypressed(key)
    if state.popup_item then
        if key == "escape" then state.popup_item = nil end
        return
    end
    -- win screen: only R
    if state.won then
        if key == "r" then
            init_game()
        end
        return
    end

    if key == "return" or key == "kpenter" then
        execute_input()

    elseif key == "tab" then
        if term.tab_candidates then
            term.tab_index = (term.tab_index % #term.tab_candidates) + 1
            term.input = term.tab_candidates[term.tab_index]
        else
            local candidates = get_completions(state, term.input)
            if #candidates == 1 then
                term.input = candidates[1]
            elseif #candidates > 1 then
                -- Strip the already-typed prefix so we display only the completing part
                local disp_before = term.input:match("%s$") and term.input
                    or (term.input:match("^(.*%s)%S+$") or "")
                local parts = {}
                for _, c in ipairs(candidates) do
                    local display = c:sub(#disp_before + 1):match("^(.-)%s*$") or ""
                    if display == "" then display = c:match("^(.-)%s*$") or c end
                    table.insert(parts, display)
                end
                push_text(table.concat(parts, "  "), "completion")
                term.tab_candidates = candidates
                term.tab_index = 1
                term.input = candidates[1]
            end
        end
        cursor_timer = 0; term.cursor_visible = true

    elseif key == "backspace" then
        clear_tab_state()
        if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
            local s = term.input:gsub("%s*%S+%s*$", "")
            if s == term.input then s = "" end
            term.input = s
            cursor_timer = 0; term.cursor_visible = true
        else
            local off = utf8.offset(term.input, -1)
            if off then
                term.input = term.input:sub(1, off - 1)
            end
        end

    elseif key == "w" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
        clear_tab_state()
        local s = term.input:gsub("%s*%S+%s*$", "")
        if s == term.input then s = "" end
        term.input = s
        cursor_timer = 0; term.cursor_visible = true

    elseif key == "u" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
        clear_tab_state()
        term.input = ""
        cursor_timer = 0; term.cursor_visible = true

    elseif key == "up" then
        clear_tab_state()
        if #term.history > 0 then
            if term.history_index == nil then
                term.history_index = #term.history
            else
                term.history_index = math.max(1, term.history_index - 1)
            end
            term.input = term.history[term.history_index]
        end

    elseif key == "down" then
        clear_tab_state()
        if term.history_index then
            term.history_index = term.history_index + 1
            if term.history_index > #term.history then
                term.history_index = nil
                term.input = ""
            else
                term.input = term.history[term.history_index]
            end
        end

    elseif key == "pageup" then
        term.scroll = term.scroll + 5

    elseif key == "pagedown" then
        term.scroll = math.max(0, term.scroll - 5)

    elseif key == "home" then
        term.scroll = math.max(0, #term.lines - 10)

    elseif key == "end" then
        term.scroll = 0
    end
end

function love.mousepressed(x, y, button)
    if button == 1 and state.popup_item and Render.popup_close_rect then
        local r = Render.popup_close_rect
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            state.popup_item = nil
        end
    end
end
