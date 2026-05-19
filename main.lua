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

local function init_game()
    state = World.new_state()
    term = {
        lines          = {},
        input          = "",
        scroll         = 0,
        cursor_visible = true,
        history        = {},
        history_index  = nil,
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
    local input = term.input
    term.input         = ""
    term.scroll        = 0
    term.history_index = nil

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
    term.input = term.input .. t
end

function love.keypressed(key)
    if state.popup_item then
        if key == "escape" then state.popup_item = nil end
        return
    end
    -- win screen: only R / Esc
    if state.won then
        if key == "escape" then
            love.event.quit()
        elseif key == "r" then
            init_game()
        end
        return
    end

    if key == "escape" then
        love.event.quit()

    elseif key == "return" or key == "kpenter" then
        execute_input()

    elseif key == "backspace" then
        local off = utf8.offset(term.input, -1)
        if off then
            term.input = term.input:sub(1, off - 1)
        end

    elseif key == "up" then
        if #term.history > 0 then
            if term.history_index == nil then
                term.history_index = #term.history
            else
                term.history_index = math.max(1, term.history_index - 1)
            end
            term.input = term.history[term.history_index]
        end

    elseif key == "down" then
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
