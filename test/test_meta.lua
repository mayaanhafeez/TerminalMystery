-- test/test_meta.lua — commands/meta.lua: accuse, help gating, exit variants.
--
-- exit (and vim, indirectly) reach through the GameScreen / Save globals the
-- same way test_vim.lua's subject does, so this file stubs them the same
-- way and is required just before test_vim in test/run.lua — late enough
-- that no earlier suite sees GameScreen defined, but before test_vim
-- overwrites it with its own stub.

local T = require("test.runner")

if not love then love = {} end
if not love.timer then
    love.timer = { getTime = function() return 0 end }
end

local World    = require("world")
local Commands = require("commands.init")
local Meta     = require("commands.meta")

local save_calls, exit_to_play_calls, exit_prompt_calls
GameScreen = {
    state = nil,
    request_exit_to_play = function() exit_to_play_calls = exit_to_play_calls + 1 end,
    begin_exit_prompt = function() exit_prompt_calls = exit_prompt_calls + 1 end,
}
Save = {
    save_state = function(_, _) save_calls = save_calls + 1 end,
}

local function reset_stubs()
    save_calls, exit_to_play_calls, exit_prompt_calls = 0, 0, 0
end

-- -----------------------------------------------------------------------
T.suite("accuse — alias resolution")

for _, alias in ipairs({ "lin", "daniel", "daniel lin", "dlin", "LIN", "Daniel Lin" }) do
    T.test("'" .. alias .. "' resolves to the murderer and wins", function()
        local state = World.new_state()
        local out = Commands.execute(state, "accuse " .. alias)
        T.ok(state.won, "accuse " .. alias .. " should win")
        T.ok(out:find("Daniel Lin") or out:find("laptop"), "expected the win text")
    end)
end

T.test("a wrong name does not win and lets play continue", function()
    local state = World.new_state()
    local out = Commands.execute(state, "accuse ayesha")
    T.ok(not state.won, "wrong accusation should not win")
    T.ok(out:find("wrong person"), "expected the miss text")
end)

T.test("winning stamps won, win_time and win_commands", function()
    local state = World.new_state()
    Commands.execute(state, "help")
    Commands.execute(state, "help")
    T.eq(state.command_count, 2)
    Commands.execute(state, "accuse dlin")
    T.ok(state.won)
    T.eq(state.win_time, state.elapsed)
    T.eq(state.win_commands, state.command_count)
end)

-- -----------------------------------------------------------------------
T.suite("accuse — suspect list")

T.test("bare accuse lists all four suspects", function()
    local state = World.new_state()
    local out = Commands.execute(state, "accuse")
    for _, name in ipairs(World.suspects) do
        T.ok(out:find(name, 1, true), "expected " .. name .. " in usage text")
    end
end)

T.test("an unrecognized name lists all four suspects", function()
    local state = World.new_state()
    local out = Commands.execute(state, "accuse nobody")
    for _, name in ipairs(World.suspects) do
        T.ok(out:find(name, 1, true), "expected " .. name .. " in unknown-name text")
    end
end)

-- -----------------------------------------------------------------------
T.suite("help — grep gating")

T.test("grep is listed as locked before it unlocks", function()
    local state = World.new_state()
    T.ok(not state.unlocked.grep)
    local out = Meta.help(state, {})
    T.ok(out:find("not yet"), "expected the locked grep line")
    T.ok(not out:find("grep %-r"), "grep flags should not be listed yet")
end)

T.test("help lists grep flags once it unlocks", function()
    local state = World.new_state()
    state.unlocked.grep = true
    local out = Meta.help(state, {})
    T.ok(out:find("grep %-r"), "expected grep -r to be listed")
    T.ok(not out:find("not yet"), "the locked line should be gone")
end)

-- -----------------------------------------------------------------------
T.suite("exit — variants")

T.test("exit save writes the save and returns to play", function()
    reset_stubs()
    local state = World.new_state()
    GameScreen.state = state
    Meta.exit(state, { "save" })
    T.eq(save_calls, 1)
    T.eq(exit_to_play_calls, 1)
    T.eq(exit_prompt_calls, 0)
end)

T.test("exit nosave returns to play without saving", function()
    reset_stubs()
    local state = World.new_state()
    Meta.exit(state, { "nosave" })
    T.eq(save_calls, 0)
    T.eq(exit_to_play_calls, 1)
    T.eq(exit_prompt_calls, 0)
end)

T.test("bare exit opens the inline save prompt", function()
    reset_stubs()
    local state = World.new_state()
    Meta.exit(state, {})
    T.eq(save_calls, 0)
    T.eq(exit_to_play_calls, 0)
    T.eq(exit_prompt_calls, 1)
end)

T.test("exit is not counted toward command_count", function()
    reset_stubs()
    local state = World.new_state()
    Commands.execute(state, "help")
    T.eq(state.command_count, 1)
    Commands.execute(state, "exit nosave")
    T.eq(state.command_count, 1)
end)

T.suite("meta — map")

-- The map starts visible, so `minimap_hidden` starts false.
T.test("bare map toggles, and reports the state it moved to", function()
    local state = World.new_state()
    T.eq(Meta.map(state, {}), "Map disabled")
    T.eq(state.minimap_hidden, true)
    T.eq(Meta.map(state, {}), "Map enabled")
    T.eq(state.minimap_hidden, false)
end)

T.test("map on turns it on, and says so when it already was", function()
    local state = World.new_state()
    T.eq(Meta.map(state, { "on" }), "Map already enabled")
    state.minimap_hidden = true
    T.eq(Meta.map(state, { "on" }), "Map enabled")
    T.eq(state.minimap_hidden, false)
end)

T.test("map off turns it off, and says so when it already was", function()
    local state = World.new_state()
    T.eq(Meta.map(state, { "off" }), "Map disabled")
    T.eq(state.minimap_hidden, true)
    T.eq(Meta.map(state, { "off" }), "Map already disabled")
    T.eq(state.minimap_hidden, true)
end)

T.test("map arguments are case-insensitive", function()
    local state = World.new_state()
    T.eq(Meta.map(state, { "OFF" }), "Map disabled")
    T.eq(Meta.map(state, { "On" }), "Map enabled")
end)

T.test("an unrecognized argument explains itself and changes nothing", function()
    local state = World.new_state()
    T.eq(Meta.map(state, { "sideways" }), "Usage: map [on|off]")
    T.eq(state.minimap_hidden, false)
end)

T.test("map is reachable through execute and is unlocked from the start", function()
    local state = World.new_state()
    T.eq(Commands.execute(state, "map off"), "Map disabled")
    T.eq(state.minimap_hidden, true)
    T.eq(Commands.execute(state, "MAP ON"), "Map enabled")
end)

T.test("help lists map", function()
    local state = World.new_state()
    local out = Meta.help(state, {})
    T.ok(out:find("map %[on|off%]"), "expected map to be listed in help")
end)

T.suite("meta — terminal-only mode drops the full-view commands")

-- A terminal-only run never draws the room panel and starts with audio
-- suppressed, so map/mute/volume have nothing to act on there.
T.test("map, mute and volume are unknown words in terminal-only mode", function()
    local state = World.new_state()
    state.terminal_only = true
    for _, cmd in ipairs({ "map", "map on", "mute", "volume 50" }) do
        local out = Commands.execute(state, cmd)
        T.ok(out:find("Nothing in the house responds"),
            "expected `" .. cmd .. "` to be unknown in terminal-only mode")
    end
end)

T.test("terminal-only mode leaves the map flag alone", function()
    local state = World.new_state()
    state.terminal_only = true
    Commands.execute(state, "map off")
    T.eq(state.minimap_hidden, false)
end)

T.test("they still work in full view", function()
    local state = World.new_state()
    T.eq(state.terminal_only, false)
    T.eq(Commands.execute(state, "map off"), "Map disabled")
end)

T.test("help omits them in terminal-only mode and lists them in full view", function()
    local state = World.new_state()
    local full = Meta.help(state, {})
    T.ok(full:find("map %[on|off%]"), "expected map in the full-view help")
    T.ok(full:find("mute"), "expected mute in the full-view help")
    T.ok(full:find("volume"), "expected volume in the full-view help")

    state.terminal_only = true
    local terminal = Meta.help(state, {})
    T.ok(not terminal:find("map %[on|off%]"), "map should not be listed")
    T.ok(not terminal:find("mute"), "mute should not be listed")
    T.ok(not terminal:find("volume"), "volume should not be listed")
end)
