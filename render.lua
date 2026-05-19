-- render.lua
-- All drawing. Two panels (terminal left, room-view right) + status bar + win overlay.

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
    -- Room background wall colours (outer border)
    room_wall = {
        foyer        = {0.34, 0.30, 0.22},  -- aged oak / stone
        library      = {0.12, 0.16, 0.10},  -- dark forest green
        study        = {0.16, 0.14, 0.18},  -- deep charcoal / plum
        conservatory = {0.12, 0.22, 0.20},  -- dark teal
        cellar       = {0.09, 0.08, 0.09},  -- near-black stone
    },
    -- Floor colour (inset, lighter contrast for items)
    room_floor = {
        foyer        = {0.72, 0.66, 0.50},  -- warm cream marble
        library      = {0.28, 0.22, 0.14},  -- rich mahogany
        study        = {0.36, 0.30, 0.26},  -- warm grey carpet
        conservatory = {0.46, 0.50, 0.40},  -- mossy stone
        cellar       = {0.20, 0.18, 0.16},  -- dark rough stone
    },
    -- Item glow & label
    item_box        = {0.90, 0.70, 0.20},
    item_box_border = {0.70, 0.50, 0.10},
    item_label      = {1.00, 0.95, 0.70},
}

M.font            = nil
M.font_big        = nil
M.font_small      = nil  -- used for minimap labels
M.font_handwriting = nil   -- loaded from handwriting.ttf if present
M.popup_close_rect = nil   -- set each frame popup is drawn; nil otherwise
M.sprites    = {}   -- sprite_key -> Image (item icons)

local TILE_PATH = "assets/kenney_tiny-dungeon/Tiles/"

-- sprite key (world.lua item.sprite) -> tile filename
local SPRITE_MAP = {
    paper = "tile_0130",
    book  = "tile_0066",
    glove = "tile_0116",
}

local function load_tile(filename)
    local ok, img = pcall(love.graphics.newImage, TILE_PATH .. filename .. ".png")
    if ok then img:setFilter("nearest", "nearest") end
    return ok and img or nil
end

function M.load()
    if love.filesystem.getInfo("font.ttf") then
        M.font       = love.graphics.newFont("font.ttf", 15)
        M.font_big   = love.graphics.newFont("font.ttf", 28)
        M.font_small = love.graphics.newFont("font.ttf", 10)
    else
        M.font       = love.graphics.newFont(14)
        M.font_big   = love.graphics.newFont(26)
        M.font_small = love.graphics.newFont(10)
    end
    love.graphics.setFont(M.font)

    if love.filesystem.getInfo("handwriting.ttf") then
        M.font_handwriting = love.graphics.newFont("handwriting.ttf", 16)
    end

    for key, tile in pairs(SPRITE_MAP) do
        M.sprites[key] = load_tile(tile)
    end
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

-- Compute the screen rect of one minimap room cell given the minimap origin.
local function minimap_room_rect(room, mx, my, cell_w, cell_h, room_pad)
    local cx = mx + (room.x - 1) * cell_w
    local cy = my + (room.y - 1) * cell_h
    return cx + room_pad, cy + room_pad,
           cell_w - 2 * room_pad, cell_h - 2 * room_pad
end

-- Draw the small 3x3 minimap into the rectangle (mx, my, mw, mh).
local function draw_minimap(state, mx, my, mw, mh)
    -- background
    love.graphics.setColor(C.map_bg)
    love.graphics.rectangle("fill", mx, my, mw, mh, 4, 4)
    love.graphics.setColor(C.map_border)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", mx, my, mw, mh, 4, 4)

    local cell_w   = mw / 3
    local cell_h   = mh / 3
    local room_pad = 4

    -- connections
    love.graphics.setColor(C.connection)
    love.graphics.setLineWidth(1)
    local drawn = {}
    for id, room in pairs(World.rooms) do
        for _, exit_id in ipairs(room.exits) do
            local key = (id < exit_id) and (id .. "|" .. exit_id)
                        or (exit_id .. "|" .. id)
            if not drawn[key] then
                drawn[key] = true
                local x1, y1, w1, h1 = minimap_room_rect(room,
                    mx, my, cell_w, cell_h, room_pad)
                local x2, y2, w2, h2 = minimap_room_rect(World.rooms[exit_id],
                    mx, my, cell_w, cell_h, room_pad)
                love.graphics.line(
                    x1 + w1 / 2, y1 + h1 / 2,
                    x2 + w2 / 2, y2 + h2 / 2)
            end
        end
    end

    -- room cells
    for id, room in pairs(World.rooms) do
        local x, y, w, h = minimap_room_rect(room,
            mx, my, cell_w, cell_h, room_pad)
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
        love.graphics.rectangle("fill", x, y, w, h, 3, 3)
        love.graphics.setColor(C.map_border)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, w, h, 3, 3)

        love.graphics.setFont(M.font_small)
        love.graphics.setColor(text_color)
        -- Truncate label with "." until it fits the cell width
        local label = room.name
        local max_lw = w - 4
        if M.font_small:getWidth(label) > max_lw then
            while #label > 1 and M.font_small:getWidth(label .. ".") > max_lw do
                label = label:sub(1, -2)
            end
            label = label .. "."
        end
        local lw = M.font_small:getWidth(label)
        love.graphics.print(label,
            x + (w - lw) / 2,
            y + (h - M.font_small:getHeight()) / 2)
    end
end

-- Draw the main 2D top-down room view in the right panel.
local function draw_room_view(state)
    local px = M.MAP_X
    local py = 0
    local pw = M.MAP_W
    local ph = M.H - M.STATUS_H

    local room_id  = state.current_room
    local room_def = World.rooms[room_id]
    local wall     = C.room_wall[room_id]  or {0.18, 0.16, 0.20}
    local floor    = C.room_floor[room_id] or {0.30, 0.28, 0.26}

    -- ---- outer wall fill ----
    love.graphics.setColor(wall)
    love.graphics.rectangle("fill", px, py, pw, ph)

    -- dividing line
    love.graphics.setColor(C.map_border)
    love.graphics.setLineWidth(2)
    love.graphics.line(px, py, px, py + ph)

    -- ---- floor interior (inset 24px) ----
    local BORDER = 24
    local fx = px + BORDER
    local fy = py + BORDER
    local fw = pw - 2 * BORDER
    local fh = ph - 2 * BORDER

    love.graphics.setColor(floor)
    love.graphics.rectangle("fill", fx, fy, fw, fh, 3, 3)

    -- Subtle grout grid (very faint lines at 64px intervals)
    local GRID = 64
    love.graphics.setColor(wall[1], wall[2], wall[3], 0.18)
    love.graphics.setLineWidth(1)
    love.graphics.setScissor(fx, fy, fw, fh)
    local gx = fx + GRID
    while gx < fx + fw do
        love.graphics.line(gx, fy, gx, fy + fh)
        gx = gx + GRID
    end
    local gy = fy + GRID
    while gy < fy + fh do
        love.graphics.line(fx, gy, fx + fw, gy)
        gy = gy + GRID
    end
    love.graphics.setScissor()

    -- Inner shadow along top and left edges of floor
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.setLineWidth(4)
    love.graphics.line(fx, fy, fx + fw, fy)
    love.graphics.line(fx, fy, fx, fy + fh)

    -- ---- room name banner ----
    local BANNER_H = M.font_big:getHeight() + M.PAD
    love.graphics.setColor(0, 0, 0, 0.48)
    love.graphics.rectangle("fill", fx, fy, fw, BANNER_H, 3, 3)
    -- subtle bottom divider
    love.graphics.setColor(wall[1] + 0.15, wall[2] + 0.15, wall[3] + 0.15, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.line(fx + 8, fy + BANNER_H, fx + fw - 8, fy + BANNER_H)

    love.graphics.setFont(M.font_big)
    love.graphics.setColor(C.status_text)
    local rname = room_def.name
    local rnw   = M.font_big:getWidth(rname)
    love.graphics.print(rname, px + (pw - rnw) / 2,
        fy + (BANNER_H - M.font_big:getHeight()) / 2)

    -- ---- items ----
    local ITEM_SCALE = 5           -- 16 → 80px
    local ITEM_PX    = 16 * ITEM_SCALE
    local GLOW_R     = 34

    local ITEM_TOP    = fy + BANNER_H + M.PAD
    local ITEM_BOTTOM = fy + fh - 148
    local ITEM_LEFT   = fx + M.PAD
    local ITEM_RIGHT  = fx + fw - M.PAD
    local item_zone_w = ITEM_RIGHT - ITEM_LEFT
    local item_zone_h = ITEM_BOTTOM - ITEM_TOP

    love.graphics.setFont(M.font)
    local items = World.get_items_in_room(room_id)
    for _, item in ipairs(items) do
        local cx = ITEM_LEFT + item.x * item_zone_w
        local cy = ITEM_TOP  + item.y * item_zone_h
        local ix = cx - ITEM_PX / 2
        local iy = cy - ITEM_PX / 2

        -- Warm glow (two-pass: soft outer, brighter inner)
        love.graphics.setColor(0.95, 0.78, 0.25, 0.18)
        love.graphics.circle("fill", cx, cy, GLOW_R + 16)
        love.graphics.setColor(0.95, 0.78, 0.25, 0.42)
        love.graphics.circle("fill", cx, cy, GLOW_R)

        local spr = M.sprites[item.sprite]
        if spr then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(spr, ix, iy, 0, ITEM_SCALE, ITEM_SCALE)
        else
            love.graphics.setColor(C.item_box)
            love.graphics.rectangle("fill", ix, iy, ITEM_PX, ITEM_PX, 6, 6)
            love.graphics.setColor(C.item_box_border)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", ix, iy, ITEM_PX, ITEM_PX, 6, 6)
        end

        -- Label with drop-shadow for readability
        local label = item.filename:gsub("%.%w+$", "")
        local lw    = M.font:getWidth(label)
        local lx    = cx - lw / 2
        local ly    = iy + ITEM_PX + 4
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.print(label, lx + 1, ly + 1)
        love.graphics.setColor(C.item_label)
        love.graphics.print(label, lx, ly)
    end

    -- ---- minimap overlay (bottom-right, 160x120, inset 8px) ----
    local MM_W   = 160
    local MM_H   = 120
    local MM_INS = 8
    local mm_x   = px + pw - MM_W - MM_INS
    local mm_y   = py + ph - MM_H - MM_INS
    draw_minimap(state, mm_x, mm_y, MM_W, MM_H)
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

local function draw_popup(state)
    if not state.popup_item then
        M.popup_close_rect = nil
        return
    end

    local item = state.popup_item
    local is_book = (item.sprite == "book")

    -- Layout constants
    local DOC_W   = 440
    local DOC_H   = 580
    local BTN_W   = 130
    local BTN_H   = 34
    local BIND_W  = is_book and 22 or 36

    local doc_x = (M.W - DOC_W) / 2
    local doc_y = (M.H - DOC_H) / 2

    -- Full-screen semi-transparent overlay
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, M.W, M.H)

    -- Drop shadow
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", doc_x + 6, doc_y + 6, DOC_W, DOC_H, 6, 6)

    -- Outer frame (warm brown for paper, dark leather for book)
    local frame_r, frame_g, frame_b
    if is_book then
        frame_r, frame_g, frame_b = 0.32, 0.18, 0.10
    else
        frame_r, frame_g, frame_b = 0.55, 0.32, 0.12
    end
    love.graphics.setColor(frame_r, frame_g, frame_b)
    love.graphics.rectangle("fill", doc_x, doc_y, DOC_W, DOC_H, 6, 6)

    -- Inner parchment area
    local parch_x = doc_x + BIND_W
    local parch_y = doc_y + 10
    local parch_w = DOC_W - BIND_W - 10
    local parch_h = DOC_H - 20 - 48

    if is_book then
        love.graphics.setColor(0.93, 0.89, 0.82)
    else
        love.graphics.setColor(0.97, 0.94, 0.84)
    end
    love.graphics.rectangle("fill", parch_x, parch_y, parch_w, parch_h, 3, 3)

    -- Aged border on parchment
    love.graphics.setColor(0.70, 0.58, 0.38, 0.25)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", parch_x, parch_y, parch_w, parch_h, 3, 3)

    -- Subtle inner shadow (line rect inset 4px)
    love.graphics.setColor(0, 0, 0, 0.08)
    love.graphics.setLineWidth(8)
    love.graphics.rectangle("line",
        parch_x + 4, parch_y + 4,
        parch_w - 8, parch_h - 8, 3, 3)

    -- Binding decorations
    if is_book then
        -- Dark spine strip on the left BIND_W of the frame
        love.graphics.setColor(frame_r * 0.7, frame_g * 0.7, frame_b * 0.7)
        love.graphics.rectangle("fill", doc_x, doc_y, BIND_W, DOC_H, 6, 6)
        -- 1px white highlight at right edge of spine
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.setLineWidth(1)
        love.graphics.line(doc_x + BIND_W, doc_y, doc_x + BIND_W, doc_y + DOC_H)
    else
        -- 10 red spiral holes down the left binding strip
        local hole_zone_top    = parch_y + 10
        local hole_zone_bottom = parch_y + parch_h - 10
        local step = (hole_zone_bottom - hole_zone_top) / 9
        for i = 0, 9 do
            local hx = doc_x + BIND_W / 2
            local hy = hole_zone_top + i * step
            -- outer circle: dark brown
            love.graphics.setColor(0.15, 0.06, 0.04, 0.9)
            love.graphics.circle("fill", hx, hy, 6)
            -- inner circle: dark red
            love.graphics.setColor(0.72, 0.18, 0.12, 0.8)
            love.graphics.circle("fill", hx, hy, 4)
            -- highlight circle
            love.graphics.setColor(0.90, 0.35, 0.25, 0.5)
            love.graphics.circle("fill", hx - 1, hy - 1, 2)
        end
    end

    -- Title: strip .txt, replace underscores with spaces, capitalize each word
    local raw_title = item.filename:gsub("%.txt$", ""):gsub("_", " ")
    local title = raw_title:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)

    love.graphics.setFont(M.font)
    local title_x = parch_x + 8
    local title_y = parch_y + 10
    local title_w = parch_w - 16
    love.graphics.setColor(0.35, 0.20, 0.08)
    love.graphics.printf(title, title_x, title_y, title_w, "center")

    local title_h = M.font:getHeight()

    -- Thin horizontal divider 8px below title
    local divider_y = title_y + title_h + 8
    love.graphics.setColor(0.55, 0.40, 0.20, 0.50)
    love.graphics.setLineWidth(1)
    love.graphics.line(parch_x + 8, divider_y, parch_x + parch_w - 8, divider_y)

    -- Content text area (clipped to parchment interior)
    local tx = parch_x + 12
    local ty = divider_y + 8
    local tw = parch_w - 24

    love.graphics.setScissor(parch_x, parch_y, parch_w, parch_h)
    local text_font = M.font_handwriting or M.font
    love.graphics.setFont(text_font)
    love.graphics.setColor(0.18, 0.12, 0.06)
    love.graphics.printf(item.content, tx, ty, tw, "left")
    love.graphics.setScissor()

    -- Restore default font for close button label
    love.graphics.setFont(M.font)

    -- Close button
    local btn_x = doc_x + (DOC_W - BTN_W) / 2
    local btn_y = doc_y + DOC_H - BTN_H - 10
    love.graphics.setColor(frame_r * 1.15, frame_g * 1.15, frame_b * 1.15)
    love.graphics.rectangle("fill", btn_x, btn_y, BTN_W, BTN_H, 4, 4)
    love.graphics.setColor(0.97, 0.90, 0.72)
    love.graphics.printf("Close  [Esc]", btn_x, btn_y + (BTN_H - M.font:getHeight()) / 2, BTN_W, "center")
    M.popup_close_rect = { x = btn_x, y = btn_y, w = BTN_W, h = BTN_H }
end

function M.draw(state, term, best)
    love.graphics.setColor(C.bg)
    love.graphics.rectangle("fill", 0, 0, M.W, M.H)
    draw_terminal(state, term)
    draw_room_view(state)
    draw_status_bar(state)
    if state.won then
        draw_win_screen(state, best)
    end
    draw_popup(state)
end

return M
