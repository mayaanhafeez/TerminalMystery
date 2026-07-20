-- test/test_evidence.lua — sed substitution + the chmod-write / sed -i puzzle

local T = require("test.runner")
local World = require("world")
local Evidence = require("commands.evidence")
local Items = require("commands.items")

local function make_state(current, visited_list)
    local s = World.new_state()
    s.current_room = current or "foyer"
    s.visited = {}
    for _, id in ipairs(visited_list or { current or "foyer" }) do
        s.visited[id] = true
    end
    return s
end

-- -----------------------------------------------------------------------
T.suite("sed — substitution (read-only, no -i)")

T.test("literal s/// prints the transformed text, file untouched", function()
    local s = make_state("server_room")
    local out = Evidence.sed(s, {"s/svc-agent/dlin/", "audit_stream.log"})
    T.ok(out:find("10:04:07  dlin  scan  den", 1, true), "expected substituted line: " .. out)
    T.ok(World.rooms.server_room.items["audit_stream.log"].content:find("svc-agent", 1, true),
        "content should still contain svc-agent (no -i)")
end)

T.test("g replaces every occurrence on a line", function()
    local s = make_state("foyer")
    World.rooms.foyer.items["welcome.txt"].content = "aaa bbb aaa"
    local first = Evidence.sed(s, {"s/aaa/X/", "welcome.txt"})
    local all   = Evidence.sed(s, {"s/aaa/X/g", "welcome.txt"})
    T.eq(first, "X bbb aaa")
    T.eq(all, "X bbb X")
end)

-- The slack_draft → slack_final intro puzzle: deleting the literal parenthetical
-- reproduces the sent message body.
T.test("deleting the cellar clause reproduces slack_final's body", function()
    local s = make_state("server_room")
    local out = Evidence.sed(s, {
        "s/ (stepped out ~5 min around 10 to grab something from the cellar)//",
        ".slack_draft.txt",
    })
    local final_body = "  in the home office all night fighting a deploy, "
        .. "didn't even hear the emacs/vim thing kick off lol"
    T.ok(out:find(final_body, 1, true), "expected the trimmed message body: " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("sed -i — in-place edit needs write permission")

T.test("sed -i on a read-only file is denied with a chmod hint", function()
    local s = make_state("server_room")
    local out = Evidence.sed(s, {"-i", "s/svc-agent/dlin/g", "audit_stream.log"})
    T.ok(out:find("Permission denied", 1, true), "expected permission denied: " .. out)
    T.ok(out:find("chmod %+w"), "expected chmod +w hint: " .. out)
end)

T.test("chmod +w then sed -i rewrites content; cat sees the new text", function()
    local s = make_state("server_room")
    Items.chmod(s, {"+w", "audit_stream.log"})
    local out = Evidence.sed(s, {"-i", "s/svc-agent/dlin/g", "audit_stream.log"})
    T.ok(out:find("edited"), "expected success message: " .. out)
    local shown = Evidence.cat(s, {"audit_stream.log"})
    T.ok(shown:find("10:12:31  dlin  scan  cellar", 1, true),
        "cat should show the restored dlin handle: " .. shown)
    T.ok(not shown:find("svc-agent", 1, true), "svc-agent should be fully replaced")
end)
