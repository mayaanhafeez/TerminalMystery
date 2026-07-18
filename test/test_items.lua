-- test/test_items.lua — mv, cp, rm, chmod

local T = require("test.runner")
local World = require("world")
local Items = require("commands.items")
local Registry = require("items")

local function Items_registry_has(id)
    return Registry.registry[id] ~= nil
end

local function make_state(current, visited_list)
    local s = World.new_state()
    s.current_room = current or "foyer"
    s.visited = {}
    for _, id in ipairs(visited_list or { current or "foyer" }) do
        s.visited[id] = true
    end
    return s
end

-- Restore an item to its original room (used to clean up after mv tests)
local function move_item_back(filename, from_room, to_room)
    local item = World.rooms[from_room].items[filename]
    if item then
        World.rooms[from_room].items[filename] = nil
        World.rooms[to_room].items[filename] = item
        item.room = to_room
    end
end

-- -----------------------------------------------------------------------
T.suite("mv — basic")

T.test("mv moves file to another visited room", function()
    local s = make_state("sunroom", {"sunroom", "foyer", "cellar"})
    Items.mv(s, {"espresso_bar.txt", "Cellar"})
    T.ok(World.rooms.cellar.items["espresso_bar.txt"], "item should be in cellar")
    T.nil_(World.rooms.sunroom.items["espresso_bar.txt"], "item should be gone from sunroom")
    move_item_back("espresso_bar.txt", "cellar", "sunroom")
end)

T.test("mv updates item.room field", function()
    local s = make_state("sunroom", {"sunroom", "foyer", "cellar"})
    Items.mv(s, {"espresso_bar.txt", "Cellar"})
    T.eq(World.rooms.cellar.items["espresso_bar.txt"].room, "cellar")
    move_item_back("espresso_bar.txt", "cellar", "sunroom")
end)

T.test("mv ../Room resolves relative path", function()
    local s = make_state("sunroom", {"sunroom", "foyer", "cellar"})
    Items.mv(s, {"espresso_bar.txt", "../Cellar"})
    T.ok(World.rooms.cellar.items["espresso_bar.txt"], "item should be in cellar via ../Cellar")
    move_item_back("espresso_bar.txt", "cellar", "sunroom")
end)

T.test("mv fails for nonexistent source file", function()
    local s = make_state("foyer", {"foyer", "cellar"})
    local out = Items.mv(s, {"ghost.txt", "Cellar"})
    T.ok(out:find("no such file"), "expected 'no such file': " .. out)
end)

T.test("mv fails for unvisited destination", function()
    local s = make_state("sunroom", {"sunroom"})
    local out = Items.mv(s, {"espresso_bar.txt", "Cellar"})
    T.ok(out:find("no such visited"), "expected 'no such visited room': " .. out)
end)

T.test("mv fails when source and destination are the same room", function()
    local s = make_state("sunroom", {"sunroom"})
    local out = Items.mv(s, {"espresso_bar.txt", "Sunroom"})
    T.ok(out:find("same room"), "expected same-room error: " .. out)
end)

T.test("mv fails for nonexistent destination", function()
    local s = make_state("foyer", {"foyer"})
    local out = Items.mv(s, {"welcome.txt", "Ballroom"})
    T.ok(out:find("no such"), "expected no-such error: " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("mv — cross-room source path")

T.test("mv home_office/draft_email.txt cellar moves from home_office", function()
    local s = make_state("foyer", {"foyer", "home_office", "cellar"})
    Items.mv(s, {"home_office/draft_email.txt", "Cellar"})
    T.ok(World.rooms.cellar.items["draft_email.txt"], "item should be in cellar")
    T.nil_(World.rooms.home_office.items["draft_email.txt"], "item should be gone from home_office")
    move_item_back("draft_email.txt", "cellar", "home_office")
end)

-- -----------------------------------------------------------------------
T.suite("cp — basic")

T.test("cp copies file to another visited room", function()
    local s = make_state("home_office", {"home_office", "foyer", "cellar"})
    Items.cp(s, {"draft_email.txt", "Cellar"})
    T.ok(World.rooms.cellar.items["draft_email.txt"], "copy should be in cellar")
    T.ok(World.rooms.home_office.items["draft_email.txt"], "original should still be in home_office")
    -- cleanup
    World.rooms.cellar.items["draft_email.txt"] = nil
end)

T.test("cp ../Room resolves relative path", function()
    local s = make_state("home_office", {"home_office", "foyer", "cellar"})
    Items.cp(s, {"draft_email.txt", "../Cellar"})
    T.ok(World.rooms.cellar.items["draft_email.txt"], "copy via ../Cellar should be in cellar")
    World.rooms.cellar.items["draft_email.txt"] = nil
end)

T.test("cp fails when file already exists at destination", function()
    local s = make_state("foyer", {"foyer", "home_office"})
    World.rooms.home_office.items["welcome.txt"] =
        { id="dup", filename="welcome.txt", room="home_office", content="" }
    local out = Items.cp(s, {"welcome.txt", "home_office"})
    T.ok(out:find("already exists"), "expected 'already exists': " .. out)
    World.rooms.home_office.items["welcome.txt"] = nil
end)

T.test("cp fails for unvisited destination", function()
    local s = make_state("home_office", {"home_office"})
    local out = Items.cp(s, {"draft_email.txt", "Cellar"})
    T.ok(out:find("no such visited"), "expected unvisited-room error: " .. out)
end)

T.test("cp <file> <newname> copies within the current room", function()
    local s = make_state("home_office", {"home_office"})
    Items.cp(s, {"draft_email.txt", "draft_copy.txt"})
    local copy = World.rooms.home_office.items["draft_copy.txt"]
    T.ok(copy, "renamed copy should exist in current room")
    T.eq(copy.filename, "draft_copy.txt")
    T.eq(copy.room, "home_office")
    T.ok(World.rooms.home_office.items["draft_email.txt"], "original should remain")
    World.rooms.home_office.items["draft_copy.txt"] = nil
end)

T.test("cp <file> <room>/<newname> copies into a room under a new name", function()
    local s = make_state("home_office", {"home_office", "foyer", "cellar"})
    Items.cp(s, {"draft_email.txt", "cellar/evidence.txt"})
    local copy = World.rooms.cellar.items["evidence.txt"]
    T.ok(copy, "renamed copy should be in cellar")
    T.eq(copy.room, "cellar")
    World.rooms.cellar.items["evidence.txt"] = nil
end)

T.test("cp into a room keeps the original filename", function()
    local s = make_state("home_office", {"home_office", "foyer", "cellar"})
    Items.cp(s, {"draft_email.txt", "cellar"})
    T.ok(World.rooms.cellar.items["draft_email.txt"], "copy should keep its name in cellar")
    World.rooms.cellar.items["draft_email.txt"] = nil
end)

T.test("cp onto itself is rejected", function()
    local s = make_state("home_office", {"home_office"})
    local out = Items.cp(s, {"draft_email.txt", "draft_email.txt"})
    T.ok(out:find("same file"), "expected same-file error: " .. out)
end)

T.test("cp copy carries the registry id so content rehydrates", function()
    local s = make_state("home_office", {"home_office", "foyer", "cellar"})
    Items.cp(s, {"draft_email.txt", "cellar"})
    local copy = World.rooms.cellar.items["draft_email.txt"]
    T.eq(copy.id, "draft_email", "copy should keep the source registry id")
    T.ok(Items_registry_has(copy.id), "copy id must be a real registry key for reload")
    World.rooms.cellar.items["draft_email.txt"] = nil
end)

-- -----------------------------------------------------------------------
T.suite("rm")

T.test("rm without -f asks for confirmation", function()
    local s = make_state("home_office")
    local out = Items.rm(s, {"draft_email.txt"})
    T.ok(out:find("rm -f") or out:find("undone"), "expected confirmation prompt: " .. out)
    T.ok(World.rooms.home_office.items["draft_email.txt"], "file should still exist without -f")
end)

T.test("rm -f removes the file", function()
    local s = make_state("cellar")
    Items.rm(s, {"-f", "cellar_access_log.txt"})
    T.nil_(World.rooms.cellar.items["cellar_access_log.txt"], "file should be gone after rm -f")
    -- restore
    World.rooms.cellar.items["cellar_access_log.txt"] = {
        id = "cellar_access_log", filename = "cellar_access_log.txt", room = "cellar",
        content = "restored"
    }
end)

T.test("rm -f records in state.destroyed", function()
    local s = make_state("foyer")
    Items.rm(s, {"-f", "welcome.txt"})
    T.ok(s.destroyed["foyer/welcome.txt"], "destroyed key should be set")
    -- restore
    World.rooms.foyer.items["welcome.txt"] = {
        id = "welcome", filename = "welcome.txt", room = "foyer", content = "restored"
    }
end)

T.test("rm -f nonexistent file returns error", function()
    local s = make_state("foyer")
    local out = Items.rm(s, {"-f", "nothing.txt"})
    T.ok(out:find("no such file"), "expected 'no such file': " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("chmod — rooms")

T.test("chmod sets mode on a room without a lock_code", function()
    Items.chmod(nil, {"000", "cellar"})
    T.eq(World.rooms.cellar.mode, "000")
    World.rooms.cellar.mode = nil
end)

T.test("chmod sets mode on a file", function()
    local s = make_state("home_office")
    Items.chmod(s, {"000", "draft_email.txt"})
    T.eq(World.rooms.home_office.items["draft_email.txt"].mode, "000")
    World.rooms.home_office.items["draft_email.txt"].mode = nil
end)

T.test("chmod unknown target returns error", function()
    local s = make_state("foyer")
    local out = Items.chmod(s, {"755", "nothing"})
    T.ok(out:find("no such"), "expected no-such error: " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("chmod — lock_code room (Server Room)")

T.test("wrong code leaves the room locked", function()
    local s = make_state("foyer")
    local out = Items.chmod(s, {"755", "server_room"})
    T.eq(World.rooms.server_room.mode, "000")
    T.ok(out:find("incorrect"), "expected incorrect-code error: " .. out)
end)

T.test("correct code unlocks the room", function()
    local s = make_state("foyer")
    Items.chmod(s, {"foxglove", "server_room"})
    T.eq(World.rooms.server_room.mode, "foxglove")
end)

T.test("correct code is case-insensitive", function()
    local s = make_state("foyer")
    Items.chmod(s, {"FOXGLOVE", "server_room"})
    T.eq(World.rooms.server_room.mode, "FOXGLOVE")
end)

-- -----------------------------------------------------------------------
T.suite("chmod — file write flag")

T.test("+w makes a file writable", function()
    local s = make_state("server_room")
    Items.chmod(s, {"+w", "audit_stream.log"})
    T.eq(World.rooms.server_room.items["audit_stream.log"].writable, true)
end)

T.test("-w makes a file read-only", function()
    local s = make_state("server_room")
    Items.chmod(s, {"+w", "audit_stream.log"})
    Items.chmod(s, {"-w", "audit_stream.log"})
    T.eq(World.rooms.server_room.items["audit_stream.log"].writable, false)
end)

T.test("octal 444 is read-only, 644 grants owner write", function()
    local s = make_state("server_room")
    Items.chmod(s, {"444", "audit_stream.log"})
    T.eq(World.rooms.server_room.items["audit_stream.log"].writable, false)
    Items.chmod(s, {"644", "audit_stream.log"})
    T.eq(World.rooms.server_room.items["audit_stream.log"].writable, true)
end)
