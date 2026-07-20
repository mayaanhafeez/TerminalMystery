-- headless/play.lua — the whole game, playable in a plain terminal.
--
--   lua headless/play.lua
--   lua headless/play.lua --seed 42
--   lua headless/play.lua --script solve.txt        (replays commands, one per
--                                                      line, then drops to
--                                                      interactive)
--
-- Mirrors screens/game.lua's execute_input(): print the command's output,
-- then a blank line, same as the terminal pane does.

local root = arg[0]:match("^(.*)/headless/play%.lua$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Engine = require("headless.engine")

local seed, script_path
do
    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--seed" then
            i = i + 1
            seed = tonumber(arg[i])
        elseif a == "--script" then
            i = i + 1
            script_path = arg[i]
        end
        i = i + 1
    end
end

local session = Engine.Session.new(seed)

print(session:intro_text())
print("")

-- Returns true if the session is over (won or exited).
local function handle_result(output, meta)
    if output and output ~= "" then
        print(output)
    end
    print("")
    if meta.error then
        print("[engine error] " .. meta.error)
        return true
    end
    if meta.won then
        print(string.format("Solved in %.0fs, %d commands.", meta.elapsed, meta.command_count))
        return true
    end
    return meta.ended
end

local function run_line(line, echo)
    if echo then
        print("> " .. line)
    end
    local output, meta = session:run(line)
    return handle_result(output, meta)
end

local stopped = false

if script_path then
    local f, ferr = io.open(script_path, "r")
    if not f then
        io.stderr:write("play: cannot open script " .. script_path .. ": " .. tostring(ferr) .. "\n")
        os.exit(1)
    end
    for line in f:lines() do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
            stopped = run_line(trimmed, true)
            if stopped then break end
        end
    end
    f:close()
end

if not stopped then
    io.write("> ")
    io.flush()
    for line in io.lines() do
        stopped = run_line(line, false)
        if stopped then break end
        io.write("> ")
        io.flush()
    end
end
