-- headless/engine.lua
-- Headless adapter over the game's pure command core. Installs the minimal
-- `love.timer` shim commands/init.lua needs to stamp/measure elapsed time,
-- then wraps World + Commands behind a small session API.
--
-- Does NOT touch Save / GameScreen (the only other globals the command layer
-- ever reaches for, and only from the `exit` handler in commands/meta.lua).
-- Session:run intercepts `exit` / `quit` itself, so that handler never fires
-- headless and those globals are never needed.
--
-- Caller is responsible for putting the project root on package.path first
-- (see test/run.lua for the pattern), since this file resolves `require
-- ("world")` / `require("commands.init")` relative to that root.

if not _G.love then
    _G.love = {}
end
if not love.timer then
    -- Wall-clock, not CPU time: os.clock() barely advances while a REPL blocks
    -- on io.read waiting for a human, which would make every interactive solve
    -- read as ~0s. Prefer luasocket's sub-second gettime; fall back to
    -- os.time() (whole seconds only, but real wall-clock) when it's absent.
    local ok, socket = pcall(require, "socket")
    local clock = (ok and socket.gettime) or os.time
    love.timer = { getTime = clock }
end

local World    = require("world")
local Commands = require("commands.init")

local Session = {}
Session.__index = Session

-- seed: optional RNG seed so `cp`/`mv` re-placement (World.find_free_position)
-- is reproducible across runs (the fuzzer relies on this for repro logs).
function Session.new(seed)
    if seed then
        math.randomseed(seed)
    end
    local self = setmetatable({}, Session)
    self.state = World.new_state()
    self.ended = false
    return self
end

function Session:intro_text()
    return World.intro .. "\n\n" .. World.rooms.foyer.description
end

local function snapshot(state, ended, err)
    return {
        won = state.won,
        ended = ended or false,
        error = err,
        command_count = state.command_count,
        elapsed = state.elapsed,
        current_room = state.current_room,
    }
end

-- Runs one line of input. Returns output (string, possibly ""), meta.
-- meta = { won, ended, error, command_count, elapsed, current_room }.
-- A Lua error inside a handler is caught and reported via meta.error rather
-- than propagating, so a fuzzer can log-and-continue instead of crashing.
function Session:run(input)
    if self.ended then
        return "", snapshot(self.state, true)
    end

    local trimmed = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local first = trimmed:match("^(%S+)")
    local cmd = first and first:lower()

    if cmd == "exit" or cmd == "quit" then
        self.ended = true
        return "", snapshot(self.state, true)
    end

    -- Mirror screens/game.lua's per-frame `state.elapsed = getTime() -
    -- start_time` (screens/game.lua:349-351): that update loop doesn't exist
    -- headless, so recompute elapsed right before executing, matching what
    -- `accuse` will stamp into win_time if this command is the winning one.
    if self.state.start_time and not self.state.won then
        self.state.elapsed = love.timer.getTime() - self.state.start_time
    end

    local ok, result = pcall(Commands.execute, self.state, trimmed)
    if not ok then
        return nil, snapshot(self.state, false, tostring(result))
    end
    return result or "", snapshot(self.state, false)
end

local M = {}
M.Session = Session
M.World = World
return M
