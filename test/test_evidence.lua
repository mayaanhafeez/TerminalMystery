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

-- The slack_draft → slack_final intro puzzle: cutting the cellar admission out
-- of the draft reproduces the message Daniel actually sent. The expected body
-- is read back from slack_final.txt rather than hardcoded, so rewording the
-- evidence only ever breaks this test if the two files stop lining up.
T.test("deleting the cellar clause reproduces slack_final's body", function()
    local s = make_state("server_room")
    local out = Evidence.sed(s, {
        "s/. Did go to the cellar for 5-10 mins to grab something,/,/",
        ".slack_draft.txt",
    })
    local final = World.rooms.server_room.items["slack_final.txt"].content
    local final_body = final:match("\n(.+)$")
    T.ok(final_body, "slack_final.txt should have a message body under its header")
    T.ok(out:find(final_body, 1, true),
        "expected the trimmed message body:\n  got:      " .. out .. "\n  expected: " .. final_body)
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

-- -----------------------------------------------------------------------
T.suite("grep -r / find — reach unvisited but only unlocked rooms")

T.test("grep -r searches OPEN rooms you have not visited", function()
    -- Only the foyer is visited; foxglove lives in the (open) den and garage.
    local s = make_state("foyer", {"foyer"})
    local out = Evidence.grep(s, {"-r", "foxglove"})
    T.ok(out:find("the_den/victim.txt", 1, true), "expected a hit from the unvisited den: " .. out)
    T.ok(out:find("garage/dosage_log.txt", 1, true), "expected a hit from the unvisited garage: " .. out)
end)

T.test("find lists files in unvisited OPEN rooms", function()
    local s = make_state("foyer", {"foyer"})
    local out = Evidence.find(s, {".", "-name", "dosage_log.txt"})
    T.ok(out:find("garage/dosage_log.txt", 1, true), "expected the unvisited garage file: " .. out)
end)

T.test("a keypad-locked room stays opaque until it's opened", function()
    -- 310,000 is unique to billing_audit.txt in the locked server room.
    local s = make_state("foyer", {"foyer"})
    local locked = Evidence.grep(s, {"-r", "310,000"})
    T.eq(locked, "(no matches)")

    -- chmod opens it (no need to have visited); now the search reaches it.
    Items.chmod(s, {"765", "server_room"})
    local opened = Evidence.grep(s, {"-r", "310,000"})
    T.ok(opened:find("server_room/billing_audit.txt", 1, true),
        "expected a hit once the server room is unlocked: " .. opened)
end)

T.test("find skips a keypad-locked room until it's opened", function()
    local s = make_state("foyer", {"foyer"})
    T.eq(Evidence.find(s, {".", "-name", "billing_audit.txt"}), "(no matching files)")
    Items.chmod(s, {"765", "server_room"})
    local out = Evidence.find(s, {".", "-name", "billing_audit.txt"})
    T.ok(out:find("server_room/billing_audit.txt", 1, true), "expected the file once unlocked: " .. out)
end)

T.test("a badge-locked room is searchable only after you've been in", function()
    -- cellar_access_log.txt is unique to the badge-locked wine cellar.
    local unvisited = make_state("foyer", {"foyer"})
    T.eq(Evidence.find(unvisited, {".", "-name", "cellar_access_log.txt"}), "(no matching files)")

    local visited = make_state("foyer", {"foyer", "cellar"})
    local out = Evidence.find(visited, {".", "-name", "cellar_access_log.txt"})
    T.ok(out:find("wine_cellar/cellar_access_log.txt", 1, true),
        "expected the cellar file once you've been inside: " .. out)
end)

T.test("house-wide search still hides an undiscovered hidden room", function()
    -- The closet is a hidden room; until it's visited it stays out of results.
    local s = make_state("foyer", {"foyer"})
    local out = Evidence.find(s, {".", "-a"})
    T.ok(not out:find("draft_email_continued", 1, true),
        "the hidden closet should not surface before it's found: " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("grep — line anchors (^ / $)")

T.test("^ anchors to the start of a line", function()
    local s = make_state("server_room")
    local out = Evidence.grep(s, {"^10:04", "audit_stream.log"})
    T.ok(out:find("10:04:07", 1, true), "expected the 10:04 line: " .. out)
    T.ok(not out:find("10:01:22", 1, true), "should not match other timestamps")
end)

T.test("$ anchors to the end of a line", function()
    local s = make_state("server_room")
    local out = Evidence.grep(s, {"home_office$", "audit_stream.log"})
    T.ok(out:find("10:01:22", 1, true), "expected first home_office line")
    T.ok(out:find("10:15:48", 1, true), "expected second home_office line")
    T.ok(not out:find("scan  cellar", 1, true), "cellar line should not match")
end)

T.test("^...$ matches a whole line exactly", function()
    local s = make_state("server_room")
    local hit = Evidence.grep(s, {"^10:04:07  svc-agent  scan  den$", "audit_stream.log"})
    T.ok(hit:find("scan  den", 1, true), "expected the exact line: " .. hit)
    local miss = Evidence.grep(s, {"^svc-agent$", "audit_stream.log"})
    T.eq(miss, "(no matches)")
end)

T.test("a $ that isn't trailing is matched literally", function()
    local s = make_state("server_room")
    local out = Evidence.grep(s, {"$310", "billing_audit.txt"})
    T.ok(out:find("310,000", 1, true), "expected the $310K line: " .. out)
end)
