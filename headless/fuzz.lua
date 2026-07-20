-- headless/fuzz.lua — hunts crashes / bad states across the whole command
-- surface, and reports how much of the game a run actually covered.
--
--   lua headless/fuzz.lua --runs 200 [--seed N] [--steps 40]
--
-- Two passes:
--   1. Live-vocabulary fuzz: each step builds a command out of the CURRENT
--      state (real filenames from `ls`, real exits, visited rooms) so it goes
--      deep into rooms/unlocks, salted with noise (garbage tokens, wrong case,
--      missing files, bad paths) so it also goes wide.
--   2. Case-matrix pass: for every command, a fixed set of representative
--      argument shapes (empty, missing file, cross-room path, locked target,
--      quoted args, ...), run once each against a couple of seed states.
--
-- Every Session:run is already pcall-wrapped by headless/engine.lua, so a Lua
-- error surfaces as meta.error instead of killing the fuzzer. On any crash (or
-- a handler returning a non-string with no error) the run's full command trace
-- is written to headless/repro/ as a script `play.lua --script` can replay.

local root = arg[0]:match("^(.*)/headless/fuzz%.lua$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Engine = require("headless.engine")
local World  = Engine.World

local runs, seed, steps = 200, nil, 40
do
    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--runs" then
            i = i + 1; runs = tonumber(arg[i]) or runs
        elseif a == "--seed" then
            i = i + 1; seed = tonumber(arg[i])
        elseif a == "--steps" then
            i = i + 1; steps = tonumber(arg[i]) or steps
        end
        i = i + 1
    end
end
seed = seed or os.time()

local ALL_ROOM_IDS = {}
for id in pairs(World.rooms) do table.insert(ALL_ROOM_IDS, id) end
table.sort(ALL_ROOM_IDS)

local ALL_COMMANDS = {
    "ls", "cd", "pwd", "cwd", "cat", "grep", "find", "diff", "sed",
    "mv", "cp", "rm", "chmod", "echo", "help", "accuse",
}
local ALL_COMMANDS_SET = {}
for _, cmd in ipairs(ALL_COMMANDS) do ALL_COMMANDS_SET[cmd] = true end

-- Exploration commands get more weight so runs actually dig into rooms/files
-- instead of thrashing on the same few moves.
local WEIGHTED_COMMANDS = {}
local WEIGHT = { cd = 4, ls = 3, cat = 4, grep = 2, chmod = 1, sed = 1, mv = 1,
    cp = 1, diff = 1, find = 1, rm = 1, echo = 1, pwd = 1, cwd = 1, help = 1, accuse = 1 }
for _, cmd in ipairs(ALL_COMMANDS) do
    for _ = 1, (WEIGHT[cmd] or 1) do table.insert(WEIGHTED_COMMANDS, cmd) end
end

local JUNK = { "xyzzy", "../../etc", "*", "%", "''", "..", "~", "-9999",
    "not_a_file.txt", "DROP TABLE", "\\n", "'; rm -rf" }

local function pick(list)
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

local function maybe_case_mangle(s)
    if math.random() < 0.3 then return s:upper() end
    if math.random() < 0.3 then return s:lower() end
    return s
end

-- Lua's string-hash seed is randomized per process, so pairs() order over
-- World.rooms / state.visited / room item maps differs between separate `lua`
-- invocations even with the same math.randomseed. Sorting every pairs()-built
-- list before random selection makes a given --seed reproduce the exact same
-- generated command trace run over run (the recorded repro trace itself is
-- just literal strings and doesn't depend on this, but stable regeneration
-- matters for trusting `--seed N` as a rerun).
local function visited_rooms(state)
    local out = {}
    for id in pairs(state.visited) do table.insert(out, id) end
    table.sort(out)
    return out
end

local function sorted_exits(room_id)
    local out = World.get_exits(room_id)
    table.sort(out)
    return out
end

local function items_here(state, include_hidden)
    local out = World.get_items_in_room(state.current_room, include_hidden)
    table.sort(out, function(a, b) return a.filename < b.filename end)
    return out
end

-- Builds one command string from the session's current state, biased toward
-- legal moves with a noise floor of garbage/invalid input.
local function gen_command(state)
    if math.random() < 0.12 then
        return pick(JUNK) or ""
    end

    local cmd = pick(WEIGHTED_COMMANDS)

    if cmd == "cd" then
        local exits = sorted_exits(state.current_room)
        local choices = { "..", ".", "-", "~" }
        for _, id in ipairs(exits) do
            table.insert(choices, math.random() < 0.5 and id or World.rooms[id].name)
        end
        if math.random() < 0.15 then table.insert(choices, pick(JUNK)) end
        return "cd " .. maybe_case_mangle(pick(choices) or "")

    elseif cmd == "ls" then
        local args = {}
        if math.random() < 0.5 then table.insert(args, "-a") end
        if math.random() < 0.2 then
            local exits = sorted_exits(state.current_room)
            if #exits > 0 then table.insert(args, pick(exits)) end
        end
        return "ls " .. table.concat(args, " ")

    elseif cmd == "cat" then
        local items = items_here(state, math.random() < 0.5)
        if #items > 0 and math.random() < 0.8 then
            local it = pick(items)
            if math.random() < 0.2 then
                local rooms = visited_rooms(state)
                return "cat " .. pick(rooms) .. "/" .. it.filename
            end
            return "cat " .. it.filename
        end
        return "cat " .. (pick(JUNK) or "missing.txt")

    elseif cmd == "grep" then
        local flag_pool = { "", "-r", "-v", "-n", "-l", "-a", "-rn", "-rl", "-ra" }
        local pattern_pool = { "foxglove", "dlin", "cellar", "^", "$", "svc-agent",
            "lin", pick(JUNK) or "zz" }
        local parts = { "grep", pick(flag_pool) or "" }
        table.insert(parts, pick(pattern_pool) or "x")
        if math.random() < 0.3 then table.insert(parts, "*") end
        if math.random() < 0.2 then table.insert(parts, ".[^.]*") end
        if math.random() < 0.3 then
            local items = items_here(state, true)
            if #items > 0 then table.insert(parts, pick(items).filename) end
        end
        return table.concat(parts, " ")

    elseif cmd == "find" then
        local pool = { "log", "note", "*.txt", "keycard", pick(JUNK) or "x" }
        local args = { "find", pick(pool) }
        if math.random() < 0.4 then table.insert(args, "-a") end
        return table.concat(args, " ")

    elseif cmd == "diff" then
        local items = items_here(state, true)
        local rooms = visited_rooms(state)
        local f1 = #items > 0 and pick(items).filename or pick(JUNK)
        local f2 = #items > 1 and pick(items).filename or (pick(rooms) or "x")
        return "diff " .. f1 .. " " .. f2

    elseif cmd == "sed" then
        local items = items_here(state, true)
        local target = #items > 0 and pick(items).filename or "missing.txt"
        local script_pool = {
            "s/svc-agent/dlin/g", "s/a/b/", "s/foo/bar/g",
            "s///", "not-a-script", "s/x/y",
        }
        local prefix = math.random() < 0.5 and "sed -i " or "sed "
        return prefix .. "'" .. (pick(script_pool) or "s/a/b/") .. "' " .. target

    elseif cmd == "mv" or cmd == "cp" then
        local items = items_here(state, true)
        local rooms = visited_rooms(state)
        local src = #items > 0 and pick(items).filename or "missing.txt"
        local dst = pick(rooms) or "foyer"
        if cmd == "cp" and math.random() < 0.3 then
            dst = "renamed_" .. tostring(math.random(9999)) .. ".txt"
        end
        return cmd .. " " .. src .. " " .. dst

    elseif cmd == "rm" then
        local items = items_here(state, true)
        local target = #items > 0 and pick(items).filename or "missing.txt"
        local prefix = math.random() < 0.5 and "rm -f " or "rm "
        return prefix .. target

    elseif cmd == "chmod" then
        local mode_pool = { "+w", "-w", "765", "000", "u+w", "rw-", pick(JUNK) or "??" }
        local target_pool = {}
        for _, id in ipairs(ALL_ROOM_IDS) do table.insert(target_pool, id) end
        for _, it in ipairs(items_here(state, true)) do table.insert(target_pool, it.filename) end
        return "chmod " .. (pick(mode_pool) or "+w") .. " " .. (pick(target_pool) or "x")

    elseif cmd == "echo" then
        return "echo " .. (pick(JUNK) or "hello") .. " " .. tostring(math.random(999))

    elseif cmd == "accuse" then
        -- Mostly red herrings/garbage so runs don't win-and-stop immediately;
        -- occasionally feed the real answer so the win path gets exercised too.
        local pool = { "ayesha", "wei", "priya", "nobody", pick(JUNK) or "x" }
        if math.random() < 0.08 then table.insert(pool, "lin") end
        return "accuse " .. pick(pool)

    elseif cmd == "pwd" or cmd == "cwd" or cmd == "help" then
        return cmd
    end

    return cmd
end

-- ---------------------------------------------------------------------------
-- Live-vocabulary fuzz
-- ---------------------------------------------------------------------------

local repro_dir = root .. "/headless/repro"
os.execute("mkdir -p " .. repro_dir)

local crashes = {}
local coverage = {
    commands_hit = {},
    rooms_visited = {},
    files_read = {},
    wins = 0,
}

local function write_repro(run_seed, trace, failure)
    local path = repro_dir .. "/run_" .. run_seed .. ".txt"
    local f = io.open(path, "w")
    if f then
        f:write("# fuzz repro — seed " .. run_seed .. "\n")
        f:write("# failure: " .. failure .. "\n")
        f:write("# replay with: lua headless/play.lua --seed " .. run_seed
            .. " --script " .. path .. "\n")
        for _, line in ipairs(trace) do
            f:write(line .. "\n")
        end
        f:close()
    end
    return path
end

math.randomseed(seed)

for run_i = 1, runs do
    local run_seed = seed + run_i
    local session = Engine.Session.new(run_seed)
    local trace = {}

    for _ = 1, steps do
        local cmd = gen_command(session.state)
        table.insert(trace, cmd)
        local output, meta = session:run(cmd)

        local first = cmd:match("^(%S+)")
        if first and ALL_COMMANDS_SET[first:lower()] then
            coverage.commands_hit[first:lower()] = true
        end
        for id in pairs(session.state.visited) do coverage.rooms_visited[id] = true end
        for k in pairs(session.state.files_read) do coverage.files_read[k] = true end

        if meta.error then
            local path = write_repro(run_seed, trace, meta.error)
            table.insert(crashes, { seed = run_seed, error = meta.error, repro = path })
            break
        end
        if output ~= nil and type(output) ~= "string" then
            local path = write_repro(run_seed, trace, "non-string output: " .. tostring(output))
            table.insert(crashes, { seed = run_seed, error = "non-string output", repro = path })
            break
        end
        if meta.won then
            coverage.wins = coverage.wins + 1
            break
        end
        if meta.ended then
            break
        end
    end
end

-- ---------------------------------------------------------------------------
-- Case-matrix pass — one representative shape per command, no crash allowed.
-- ---------------------------------------------------------------------------

local CASE_MATRIX = {
    ls    = { "", "-a", "-Z", "bogus_room" },
    cd    = { "", "..", "-", "~", "bogus_room", "Home_Office" },
    pwd   = { "" },
    cwd   = { "" },
    cat   = { "", "welcome.txt", "missing.txt", "foyer/welcome.txt", "\"welcome.txt\"" },
    grep  = { "", "-r foxglove", "-v -n dlin *", "-rl foxglove", "^F", "x$" },
    find  = { "", "-name log", "*.txt -a" },
    diff  = { "", "a b", "welcome.txt welcome.txt" },
    sed   = { "", "'s/a/b/' welcome.txt", "-i 's/a/b/' welcome.txt", "'bogus' welcome.txt" },
    mv    = { "", "missing.txt foyer", "welcome.txt bogus_room" },
    cp    = { "", "missing.txt foyer", "welcome.txt foyer" },
    rm    = { "", "missing.txt", "-f missing.txt" },
    chmod = { "", "+w missing.txt", "000 foyer", "765 foyer", "bogus target" },
    echo  = { "", "hello world", "\"quoted text\"" },
    help  = { "" },
    accuse = { "", "nobody", "lin", "daniel lin" },
    exit  = { "", "save", "nosave" },
    quit  = { "" },
}

local matrix_failures = {}
for cmd, arg_shapes in pairs(CASE_MATRIX) do
    for _, shape in ipairs(arg_shapes) do
        local session = Engine.Session.new(seed)
        -- Give a couple of commands a warmer starting state (grep needs 2
        -- files read to unlock; diff/sed want a readable target already cat'd).
        session:run("cd home_office")
        session:run("cat draft_email.txt")
        session:run("cat repo_log.txt")
        session:run("cd ..")

        local full = (shape == "" and cmd) or (cmd .. " " .. shape)
        local output, meta = session:run(full)
        if meta.error then
            table.insert(matrix_failures, { cmd = full, error = meta.error })
        elseif output ~= nil and type(output) ~= "string" then
            table.insert(matrix_failures, { cmd = full, error = "non-string output" })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

print(string.format("fuzz: %d runs x %d steps (base seed %d)", runs, steps, seed))
print(string.format("  commands exercised: %d / %d", count_keys(coverage.commands_hit), #ALL_COMMANDS))
print(string.format("  rooms visited:       %d / %d", count_keys(coverage.rooms_visited), #ALL_ROOM_IDS))
print(string.format("  distinct files read: %d", count_keys(coverage.files_read)))
print(string.format("  wins reached:        %d", coverage.wins))
print(string.format("  live-vocab crashes:  %d", #crashes))
print(string.format("  case-matrix failures:%d", #matrix_failures))

if #crashes > 0 then
    print("\nCrashes (live-vocabulary fuzz):")
    for _, c in ipairs(crashes) do
        print(string.format("  seed %d: %s\n    repro: %s", c.seed, c.error, c.repro))
    end
end

if #matrix_failures > 0 then
    print("\nCase-matrix failures:")
    for _, f in ipairs(matrix_failures) do
        print(string.format("  %-45s %s", f.cmd, f.error))
    end
end

if #crashes > 0 or #matrix_failures > 0 then
    os.exit(1)
end
