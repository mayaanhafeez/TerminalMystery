-- test/test_items.lua — mv, cp, rm, chmod

local T = require("test.runner")
local World = require("world")
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
    local s = make_state("conservatory", {"conservatory", "foyer", "cellar"})
    Items.mv(s, {"tea_service.txt", "Cellar"})
    T.ok(World.rooms.cellar.items["tea_service.txt"], "item should be in cellar")
    T.nil_(World.rooms.conservatory.items["tea_service.txt"], "item should be gone from conservatory")
    move_item_back("tea_service.txt", "cellar", "conservatory")
end)

T.test("mv updates item.room field", function()
    local s = make_state("conservatory", {"conservatory", "foyer", "cellar"})
    Items.mv(s, {"tea_service.txt", "Cellar"})
    T.eq(World.rooms.cellar.items["tea_service.txt"].room, "cellar")
    move_item_back("tea_service.txt", "cellar", "conservatory")
end)

T.test("mv ../Room resolves relative path", function()
    local s = make_state("conservatory", {"conservatory", "foyer", "cellar"})
    Items.mv(s, {"tea_service.txt", "../Cellar"})
    T.ok(World.rooms.cellar.items["tea_service.txt"], "item should be in cellar via ../Cellar")
    move_item_back("tea_service.txt", "cellar", "conservatory")
end)

T.test("mv fails for nonexistent source file", function()
    local s = make_state("foyer", {"foyer", "cellar"})
    local out = Items.mv(s, {"ghost.txt", "Cellar"})
    T.ok(out:find("no such file"), "expected 'no such file': " .. out)
end)

T.test("mv fails for unvisited destination", function()
    local s = make_state("conservatory", {"conservatory"})
    local out = Items.mv(s, {"tea_service.txt", "Cellar"})
    T.ok(out:find("no such visited"), "expected 'no such visited room': " .. out)
end)

T.test("mv fails when source and destination are the same room", function()
    local s = make_state("conservatory", {"conservatory"})
    local out = Items.mv(s, {"tea_service.txt", "Conservatory"})
    T.ok(out:find("same room"), "expected same-room error: " .. out)
end)

T.test("mv fails for nonexistent destination", function()
    local s = make_state("foyer", {"foyer"})
    local out = Items.mv(s, {"welcome.txt", "Ballroom"})
    T.ok(out:find("no such"), "expected no-such error: " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("mv — cross-room source path")

T.test("mv library/torn_letter.txt cellar moves from library", function()
    local s = make_state("foyer", {"foyer", "library", "cellar"})
    Items.mv(s, {"Library/torn_letter.txt", "Cellar"})
    T.ok(World.rooms.cellar.items["torn_letter.txt"], "item should be in cellar")
    T.nil_(World.rooms.library.items["torn_letter.txt"], "item should be gone from library")
    move_item_back("torn_letter.txt", "cellar", "library")
end)

-- -----------------------------------------------------------------------
T.suite("cp — basic")

T.test("cp copies file to another visited room", function()
    local s = make_state("library", {"library", "foyer", "cellar"})
    Items.cp(s, {"torn_letter.txt", "Cellar"})
    T.ok(World.rooms.cellar.items["torn_letter.txt"], "copy should be in cellar")
    T.ok(World.rooms.library.items["torn_letter.txt"], "original should still be in library")
    -- cleanup
    World.rooms.cellar.items["torn_letter.txt"] = nil
end)

T.test("cp ../Room resolves relative path", function()
    local s = make_state("library", {"library", "foyer", "cellar"})
    Items.cp(s, {"torn_letter.txt", "../Cellar"})
    T.ok(World.rooms.cellar.items["torn_letter.txt"], "copy via ../Cellar should be in cellar")
    World.rooms.cellar.items["torn_letter.txt"] = nil
end)

T.test("cp fails when file already exists at destination", function()
    local s = make_state("foyer", {"foyer", "library"})
    -- welcome.txt is in foyer; let's try to cp a file that already exists in library
    -- First manually place a copy
    World.rooms.library.items["welcome.txt"] = { id="dup", filename="welcome.txt", room="library", content="" }
    local out = Items.cp(s, {"welcome.txt", "Library"})
    T.ok(out:find("already exists"), "expected 'already exists': " .. out)
    World.rooms.library.items["welcome.txt"] = nil
end)

T.test("cp fails for unvisited destination", function()
    local s = make_state("library", {"library"})
    local out = Items.cp(s, {"torn_letter.txt", "Cellar"})
    T.ok(out:find("no such visited"), "expected unvisited-room error: " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("rm")

T.test("rm without -f asks for confirmation", function()
    local s = make_state("library")
    local out = Items.rm(s, {"torn_letter.txt"})
    T.ok(out:find("rm -f") or out:find("undone"), "expected confirmation prompt: " .. out)
    T.ok(World.rooms.library.items["torn_letter.txt"], "file should still exist without -f")
end)

T.test("rm -f removes the file", function()
    local s = make_state("cellar")
    Items.rm(s, {"-f", "wine_inventory.txt"})
    T.nil_(World.rooms.cellar.items["wine_inventory.txt"], "file should be gone after rm -f")
    -- restore
    World.rooms.cellar.items["wine_inventory.txt"] = {
        id = "wine_inventory", filename = "wine_inventory.txt", room = "cellar",
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
T.suite("chmod")

T.test("chmod sets mode on a room", function()
    Items.chmod(nil, {"000", "cellar"})
    T.eq(World.rooms.cellar.mode, "000")
    World.rooms.cellar.mode = nil
end)

T.test("chmod sets mode on a file", function()
    local s = make_state("library")
    Items.chmod(s, {"000", "torn_letter.txt"})
    T.eq(World.rooms.library.items["torn_letter.txt"].mode, "000")
    World.rooms.library.items["torn_letter.txt"].mode = nil
end)

T.test("chmod unknown target returns error", function()
    local s = make_state("foyer")
    local out = Items.chmod(s, {"755", "nothing"})
    T.ok(out:find("no such"), "expected no-such error: " .. out)
end)
