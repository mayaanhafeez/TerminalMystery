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

    -- Snapshot the pristine room/file layout for completionist coverage
    -- tracking (Session:coverage). Taken once, here, because mv/cp/rm mutate
    -- World.rooms as the game runs, and "have you seen everything" should
    -- mean the original layout, not whatever's left after files get moved
    -- around or destroyed.
    self.total_rooms = {}
    for id in pairs(World.rooms) do
        table.insert(self.total_rooms, id)
    end
    table.sort(self.total_rooms)

    self.total_files = {}
    for _, room_id in ipairs(self.total_rooms) do
        local fnames = {}
        for filename in pairs(World.rooms[room_id].items) do
            table.insert(fnames, filename)
        end
        table.sort(fnames)
        for _, filename in ipairs(fnames) do
            table.insert(self.total_files, room_id .. "/" .. filename)
        end
    end

    return self
end

function Session:intro_text()
    return World.intro .. "\n\n" .. World.rooms.foyer.description
end

-- ~/room/subroom style path for the current room — same notation `pwd`
-- prints (commands/navigation.lua's local room_path, duplicated here since
-- it isn't exported). Exposed so a driver can remind an LLM player exactly
-- where it is every turn without spending a real `pwd` command: the room
-- tree isn't flat (most rooms are only reachable via `cd ..` first), and a
-- player/model that only sees prose descriptions easily loses track of it.
function Session:current_path()
    local parts = {}
    local id = self.state.current_room
    while id do
        table.insert(parts, World.rooms[id].id)
        id = World.rooms[id].parent
    end
    local n = #parts
    for i = 1, math.floor(n / 2) do
        parts[i], parts[n - i + 1] = parts[n - i + 1], parts[i]
    end
    parts[1] = "~"
    if n == 1 then return "~" end
    return table.concat(parts, "/")
end

-- Completionist coverage against the pristine snapshot taken at Session.new.
-- Used by the `__coverage__` query below and by headless/serve.lua's STATUS
-- line (for a driver that wants to gate on "has everything been seen yet").
function Session:coverage()
    local rooms_visited = 0
    for _ in pairs(self.state.visited) do
        rooms_visited = rooms_visited + 1
    end
    local files_read = 0
    for _ in pairs(self.state.files_read) do
        files_read = files_read + 1
    end

    local missing_rooms = {}
    for _, id in ipairs(self.total_rooms) do
        if not self.state.visited[id] then
            table.insert(missing_rooms, id)
        end
    end
    local missing_files = {}
    for _, path in ipairs(self.total_files) do
        if not self.state.files_read[path] then
            table.insert(missing_files, path)
        end
    end

    return {
        rooms_visited = rooms_visited,
        rooms_total = #self.total_rooms,
        files_read = files_read,
        files_total = #self.total_files,
        missing_rooms = missing_rooms,
        missing_files = missing_files,
    }
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

    -- Debug/QA-only query, not part of the in-game `help` vocabulary: reports
    -- completionist progress against the pristine snapshot. Doesn't touch
    -- command_count/elapsed since it isn't a real investigative move.
    if cmd == "__coverage__" then
        local cov = self:coverage()
        local lines = {
            string.format("Rooms visited: %d/%d", cov.rooms_visited, cov.rooms_total),
        }
        if #cov.missing_rooms > 0 then
            table.insert(lines, "  Not yet visited: " .. table.concat(cov.missing_rooms, ", "))
        end
        table.insert(lines, string.format("Files read: %d/%d", cov.files_read, cov.files_total))
        if #cov.missing_files > 0 then
            table.insert(lines, "  Not yet read: " .. table.concat(cov.missing_files, ", "))
        end
        return table.concat(lines, "\n"), snapshot(self.state, false)
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
