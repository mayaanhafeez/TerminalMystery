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
