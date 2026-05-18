-- render.lua
-- All drawing. Two panels (terminal left, map right) + status bar + win overlay.

local World = require("world")

local M = {}

-- Window layout
M.W        = 1280
M.H        = 800
M.STATUS_H = 28
M.TERM_W   = 760
M.MAP_X    = M.TERM_W
M.MAP_W    = M.W - M.TERM_W
M.PAD      = 14

-- Palette
local C = {
    bg              = {0.05, 0.06, 0.09},
    term_bg         = {0.02, 0.03, 0.04},
    term_text       = {0.55, 0.95, 0.55},
    term_dim        = {0.30, 0.55, 0.30},
    term_user       = {0.85, 0.95, 0.85},
    prompt          = {0.95, 0.75, 0.25},
    system          = {0.95, 0.80, 0.40},
    map_bg          = {0.10, 0.12, 0.16},
    map_border      = {0.16, 0.18, 0.22},
    room_unvisited  = {0.18, 0.20, 0.24},
    room_visited    = {0.32, 0.36, 0.44},
    room_current    = {0.95, 0.70, 0.25},
    room_text_dim   = {0.40, 0.42, 0.48},
    room_text       = {0.88, 0.88, 0.92},
    room_text_curr  = {0.10, 0.10, 0.10},
    status_bg       = {0.12, 0.14, 0.18},
    status_text     = {0.80, 0.80, 0.85},
    connection      = {0.42, 0.45, 0.55},
    win_overlay     = {0, 0, 0, 0.88},
    win_title       = {0.95, 0.85, 0.45},
    win_text        = {0.90, 0.95, 0.90},
    win_record      = {0.95, 0.50, 0.50},
}

M.font     = nil
M.font_big = nil

function M.load()
    -- Use a bundled font.ttf if the player drops one in; otherwise
    -- fall back to LÖVE's default proportional font.
    if love.filesystem.getInfo("font.ttf") then
        M.font     = love.graphics.newFont("font.ttf", 15)
        M.font_big = love.graphics.newFont("font.ttf", 28)
    else
        M.font     = love.graphics.newFont(14)
        M.font_big = love.graphics.newFont(26)
    end
    love.graphics.setFont(M.font)
end

function M.terminal_text_width()
    return M.TERM_W - 2 * M.PAD
end

-- Word-wrap a chunk of text to fit the terminal panel. Preserves leading
-- whitespace on every line (so the wrapped continuation of an indented line
-- stays indented). Returns an array of display lines.
function M.wrap_text(text)
    local font     = M.font
    local maxw     = M.terminal_text_width()
    local result   = {}
    -- iterate including trailing empty line
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        if raw == "" then
            table.insert(result, "")
        elseif font:getWidth(raw) <= maxw then
            table.insert(result, raw)
        else
            local indent = raw:match("^(%s*)") or ""
            local rest   = raw:sub(#indent + 1)
            local current = indent
            for word in rest:gmatch("%S+") do
                local sep   = (current == indent) and "" or " "
                local trial = current .. sep .. word
                if font:getWidth(trial) > maxw and current ~= indent then
                    table.insert(result, current)
                    current = indent .. word
                else
                    current = trial
                end
            end
            if current ~= indent or #result == 0 then
                table.insert(result, current)
            end
        end
    end
    return result
end

-- ---------- panels ----------

local function draw_terminal(state, term)
    love.graphics.setColor(C.term_bg)
    love.graphics.rectangle("fill", 0, 0, M.TERM_W, M.H - M.STATUS_H)

    love.graphics.setFont(M.font)
    local line_h = M.font:getHeight() * 1.25

    -- reserve one line at the bottom for the prompt
    local prompt_y = M.H - M.STATUS_H - M.PAD - line_h
    local body_top    = M.PAD
    local body_bottom = prompt_y - M.PAD
    local visible_lines = math.max(1, math.floor((body_bottom - body_top) / line_h))

    local total     = #term.lines
    local end_idx   = total - term.scroll
    if end_idx < 0 then end_idx = 0 end
    local start_idx = math.max(1, end_idx - visible_lines + 1)

    local y = body_top
    for i = start_idx, end_idx do
        local entry = term.lines[i]
        if entry then
            if entry.kind == "input" then
                love.graphics.setColor(C.term_user)
            elseif entry.kind == "system" then
                love.graphics.setColor(C.system)
            elseif entry.kind == "error" then
                love.graphics.setColor(C.win_record)
            else
                love.graphics.setColor(C.term_text)
            end
            love.graphics.print(entry.text, M.PAD, y)
        end
        y = y + line_h
    end

    -- prompt
    love.graphics.setColor(C.prompt)
    local prompt = "> "
    love.graphics.print(prompt, M.PAD, prompt_y)
    love.graphics.setColor(C.term_user)
    local px = M.PAD + M.font:getWidth(prompt)
    love.graphics.print(term.input, px, prompt_y)
    if term.cursor_visible then
        local cx = px + M.font:getWidth(term.input)
        love.graphics.setColor(C.term_user)
        love.graphics.rectangle("fill", cx, prompt_y,
            M.font:getWidth("M"), M.font:getHeight())
    end

    if term.scroll > 0 then
        love.graphics.setColor(C.term_dim)
        love.graphics.print("[ scrolled — PgDn to return ]",
            M.PAD, prompt_y - line_h)
    end
end

local function room_rect(room, grid_x, grid_top, cell_w, cell_h, room_pad)
    local cx = grid_x + (room.x - 1) * cell_w
    local cy = grid_top + (room.y - 1) * cell_h
    return cx + room_pad, cy + room_pad,
           cell_w - 2 * room_pad, cell_h - 2 * room_pad
end

local function draw_map(state)
    love.graphics.setColor(C.map_bg)
    love.graphics.rectangle("fill", M.MAP_X, 0, M.MAP_W, M.H - M.STATUS_H)

    love.graphics.setColor(C.map_border)
    love.graphics.setLineWidth(2)
    love.graphics.line(M.MAP_X, 0, M.MAP_X, M.H - M.STATUS_H)

    -- title
    love.graphics.setFont(M.font_big)
    love.graphics.setColor(C.status_text)
    love.graphics.print("Ashworth Manor", M.MAP_X + M.PAD, M.PAD)

    love.graphics.setFont(M.font)
    love.graphics.setColor(C.term_dim)
    love.graphics.print("October 14th, 1923",
        M.MAP_X + M.PAD, M.PAD + M.font_big:getHeight() + 2)

    -- 3x3 grid
    local grid_top  = M.PAD + M.font_big:getHeight() + M.font:getHeight() + 24
    local grid_x    = M.MAP_X + M.PAD
    local grid_w    = M.MAP_W - 2 * M.PAD
    local grid_h    = M.H - M.STATUS_H - grid_top - M.PAD - 30
    local cell_w    = grid_w / 3
    local cell_h    = grid_h / 3
    local room_pad  = 10

    -- connections behind rooms
    love.graphics.setColor(C.connection)
    love.graphics.setLineWidth(3)
    local drawn = {}
    for id, room in pairs(World.rooms) do
        for _, exit_id in ipairs(room.exits) do
            local key = (id < exit_id) and (id .. "|" .. exit_id)
                        or (exit_id .. "|" .. id)
            if not drawn[key] then
                drawn[key] = true
                local x1, y1, w1, h1 = room_rect(room,
                    grid_x, grid_top, cell_w, cell_h, room_pad)
                local x2, y2, w2, h2 = room_rect(World.rooms[exit_id],
                    grid_x, grid_top, cell_w, cell_h, room_pad)
                love.graphics.line(
                    x1 + w1 / 2, y1 + h1 / 2,
                    x2 + w2 / 2, y2 + h2 / 2)
            end
        end
    end

    -- rooms
    for id, room in pairs(World.rooms) do
        local x, y, w, h = room_rect(room,
            grid_x, grid_top, cell_w, cell_h, room_pad)
        local is_current = (state.current_room == id)
        local is_visited = state.visited[id] == true

        local fill, text_color
        if is_current then
            fill, text_color = C.room_current, C.room_text_curr
        elseif is_visited then
            fill, text_color = C.room_visited, C.room_text
        else
            fill, text_color = C.room_unvisited, C.room_text_dim
        end

        love.graphics.setColor(fill)
        love.graphics.rectangle("fill", x, y, w, h, 6, 6)
        love.graphics.setColor(C.map_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h, 6, 6)

        love.graphics.setColor(text_color)
        local label = room.name
        local lw = M.font:getWidth(label)
        love.graphics.print(label,
            x + (w - lw) / 2,
            y + (h - M.font:getHeight()) / 2)
    end

    -- "you are here"
    love.graphics.setColor(C.status_text)
    local note = "you are in: " .. World.rooms[state.current_room].name
    love.graphics.print(note,
        M.MAP_X + M.PAD,
        M.H - M.STATUS_H - M.PAD - M.font:getHeight())
end

local function format_time(t)
    local m = math.floor(t / 60)
    local s = t - m * 60
    return string.format("%02d:%05.2f", m, s)
end

local function draw_status_bar(state)
    love.graphics.setColor(C.status_bg)
    love.graphics.rectangle("fill", 0, M.H - M.STATUS_H, M.W, M.STATUS_H)

    love.graphics.setFont(M.font)
    love.graphics.setColor(C.status_text)
    local y = M.H - M.STATUS_H + (M.STATUS_H - M.font:getHeight()) / 2

    love.graphics.print("time:     " .. format_time(state.elapsed), M.PAD, y)
    love.graphics.print("commands: " .. tostring(state.command_count),
        M.PAD + 240, y)

    local hint = "PgUp/PgDn scroll  |  Up/Dn history  |  type `help`"
    local hw = M.font:getWidth(hint)
    love.graphics.print(hint, M.W - M.PAD - hw, y)
end

local function draw_win_screen(state, best)
    love.graphics.setColor(C.win_overlay)
    love.graphics.rectangle("fill", 0, 0, M.W, M.H)

    local lines = {}
    table.insert(lines, { f = M.font_big, c = C.win_title, t = "CASE CLOSED" })
    table.insert(lines, { f = M.font,     c = C.win_text,  t = "" })
    table.insert(lines, { f = M.font,     c = C.win_text,
        t = "You named the murderer: Dr. Reginald Croft." })
    table.insert(lines, { f = M.font,     c = C.win_text,  t = "" })

    table.insert(lines, { f = M.font_big, c = C.win_text,
        t = "this run" })
    table.insert(lines, { f = M.font,     c = C.win_text,
        t = "time:     " .. format_time(state.win_time)
            .. (state.new_time_record and "    NEW RECORD" or "") })
    table.insert(lines, { f = M.font,     c = C.win_text,
        t = "commands: " .. tostring(state.win_commands)
            .. (state.new_cmds_record and "    NEW RECORD" or "") })
    table.insert(lines, { f = M.font,     c = C.win_text,  t = "" })

    if best then
        table.insert(lines, { f = M.font_big, c = C.win_text,
            t = "personal best" })
        table.insert(lines, { f = M.font,     c = C.win_text,
            t = "fastest:        " .. format_time(best.best_time) })
        table.insert(lines, { f = M.font,     c = C.win_text,
            t = "fewest commands: " .. tostring(best.best_commands) })
    end

    table.insert(lines, { f = M.font, c = C.win_text, t = "" })
    table.insert(lines, { f = M.font, c = C.term_dim,
        t = "press R to play again,  Esc to quit" })

    -- compute total height for vertical centering
    local total_h = 0
    for _, ln in ipairs(lines) do total_h = total_h + ln.f:getHeight() * 1.35 end
    local y = (M.H - total_h) / 2
    for _, ln in ipairs(lines) do
        love.graphics.setFont(ln.f)
        local color = ln.c
        if ln.t:find("NEW RECORD", 1, true) then color = C.win_record end
        love.graphics.setColor(color)
        local lw = ln.f:getWidth(ln.t)
        love.graphics.print(ln.t, (M.W - lw) / 2, y)
        y = y + ln.f:getHeight() * 1.35
    end
end

function M.draw(state, term, best)
    love.graphics.setColor(C.bg)
    love.graphics.rectangle("fill", 0, 0, M.W, M.H)
    draw_terminal(state, term)
    draw_map(state)
    draw_status_bar(state)
    if state.won then
        draw_win_screen(state, best)
    end
end

return M
