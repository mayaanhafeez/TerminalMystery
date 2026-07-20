-- headless/serve.lua — line-protocol server over the headless engine.
--
-- Not meant to be typed at directly (that's headless/play.lua); this is the
-- back-end an external driver (headless/llm_player.py) spawns as a subprocess
-- and talks to over stdin/stdout, one command per line in, one turn's result
-- per reply out. Keeps the driver decoupled from Lua/engine internals.
--
--   lua headless/serve.lua [--seed N]
--
-- Protocol — every turn (including turn 0, the opening text, emitted before
-- any input is read) prints:
--
--   <output text, one or more lines>
--   <<END>>
--   STATUS <OK|WON|ENDED|ERROR> commands=<n> elapsed=<n> room=<room_id>
--   [ERROR_DETAIL <message>]           -- only present when STATUS is ERROR
--
-- After WON, ENDED, or ERROR the process exits (0 for WON/ENDED, 1 for
-- ERROR) — the driver should stop reading once the process exits rather than
-- waiting for another prompt.

local root = arg[0]:match("^(.*)/headless/serve%.lua$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Engine = require("headless.engine")

local seed
do
    local i = 1
    while i <= #arg do
        if arg[i] == "--seed" then
            i = i + 1
            seed = tonumber(arg[i])
        end
        i = i + 1
    end
end

local session = Engine.Session.new(seed)

-- Prints one turn's output block + sentinel + status line; returns the
-- status word so the caller can decide whether to keep looping.
local function emit(output, meta)
    io.write(output or "")
    if not output or output:sub(-1) ~= "\n" then
        io.write("\n")
    end
    io.write("<<END>>\n")

    local status
    if meta.error then
        status = "ERROR"
    elseif meta.won then
        status = "WON"
    elseif meta.ended then
        status = "ENDED"
    else
        status = "OK"
    end

    io.write(string.format(
        "STATUS %s commands=%d elapsed=%.0f room=%s\n",
        status, meta.command_count or 0, meta.elapsed or 0, meta.current_room or ""
    ))
    if meta.error then
        io.write("ERROR_DETAIL " .. tostring(meta.error):gsub("\n", " ") .. "\n")
    end
    io.flush()
    return status
end

local function exit_for(status)
    if status == "WON" or status == "ENDED" then
        os.exit(0)
    elseif status == "ERROR" then
        os.exit(1)
    end
end

-- Turn 0: opening narration, before any command has been read.
local turn0_status = emit(session:intro_text(), {
    won = false, ended = false, error = nil,
    command_count = 0, elapsed = 0, current_room = session.state.current_room,
})
exit_for(turn0_status)

for line in io.lines() do
    local output, meta = session:run(line)
    local status = emit(output, meta)
    exit_for(status)
end
