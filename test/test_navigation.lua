-- test/test_navigation.lua — cd and ls command behaviour

local T = require("test.runner")
local World = require("world")
local Nav = require("commands.navigation")

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
T.suite("cd — basic navigation")

T.test("cd into adjacent room by name", function()
    local s = make_state("foyer")
    Nav.cd(s, {"Library"})
    T.eq(s.current_room, "library")
end)

T.test("cd is case-insensitive", function()
    local s = make_state("foyer")
    Nav.cd(s, {"library"})
    T.eq(s.current_room, "library")
end)

T.test("cd marks room visited", function()
    local s = make_state("foyer")
    Nav.cd(s, {"cellar"})
    T.ok(s.visited["cellar"])
end)

T.test("cd updates previous_room", function()
    local s = make_state("foyer")
    Nav.cd(s, {"library"})
    T.eq(s.previous_room, "foyer")
end)

T.test("cd to non-adjacent existing room reports no direct path", function()
    local s = make_state("library")
    local out = Nav.cd(s, {"cellar"})
    T.ok(out:find("no direct path") or out:find("No such"), "expected 'no direct path' error, got: " .. out)
    T.eq(s.current_room, "library")
end)

T.test("cd to nonexistent room reports error", function()
    local s = make_state("foyer")
    local out = Nav.cd(s, {"Ballroom"})
    T.ok(out:find("No such") or out:find("no such"), "expected error: " .. out)
end)

T.test("cd .. goes to parent", function()
    local s = make_state("library", {"library", "foyer"})
    Nav.cd(s, {".."}); T.eq(s.current_room, "foyer")
end)

T.test("cd .. from root stays at root", function()
    local s = make_state("foyer")
    Nav.cd(s, {".."}); T.eq(s.current_room, "foyer")
end)

T.test("cd ../Cellar from library reaches cellar", function()
    local s = make_state("library", {"library", "foyer"})
    Nav.cd(s, {"../Cellar"})
    T.eq(s.current_room, "cellar")
end)

T.test("cd ../Cellar marks both intermediate and destination visited", function()
    local s = make_state("library", {"library"})
    Nav.cd(s, {"../Cellar"})
    T.ok(s.visited["foyer"], "foyer should be marked visited")
    T.ok(s.visited["cellar"], "cellar should be marked visited")
end)

T.test("cd - returns to previous room", function()
    local s = make_state("foyer")
    Nav.cd(s, {"Library"})
    Nav.cd(s, {"-"})
    T.eq(s.current_room, "foyer")
end)

T.test("cd with no args goes to root", function()
    local s = make_state("library", {"library", "foyer"})
    Nav.cd(s, {})
    T.eq(s.current_room, "foyer")
end)

-- -----------------------------------------------------------------------
T.suite("cd — locked room")

T.test("cd into chmod 000 room is denied", function()
    local s = make_state("foyer")
    World.rooms.cellar.mode = "000"
    local out = Nav.cd(s, {"Cellar"})
    World.rooms.cellar.mode = nil  -- reset
    T.ok(out:find("denied") or out:find("locked"), "expected permission denied: " .. out)
    T.eq(s.current_room, "foyer")
end)

-- -----------------------------------------------------------------------
T.suite("ls — room listing")

T.test("ls current room shows files", function()
    local s = make_state("library")
    local out = Nav.ls(s, {})
    T.ok(out:find("torn_letter.txt"), "expected torn_letter.txt in listing")
    T.ok(out:find("bookshelf_log.txt"), "expected bookshelf_log.txt in listing")
end)

T.test("ls shows exits", function()
    local s = make_state("foyer")
    local out = Nav.ls(s, {})
    T.ok(out:find("Library") or out:find("library"), "expected Library in exits")
    T.ok(out:find("Cellar") or out:find("cellar"), "expected Cellar in exits")
end)

T.test("ls does not show hidden rooms by default", function()
    local s = make_state("study")
    local out = Nav.ls(s, {})
    T.ok(not out:find("closet"), "hidden .closet should not appear without -a")
end)

T.test("ls -a shows hidden rooms", function()
    local s = make_state("study")
    local out = Nav.ls(s, {"-a"})
    T.ok(out:find(".closet"), "expected .closet with -a flag")
end)

T.test("ls <path> shows another room", function()
    local s = make_state("foyer")
    local out = Nav.ls(s, {"Library"})
    T.ok(out:find("torn_letter.txt"), "expected library files")
end)

T.test("ls ../ from library shows foyer", function()
    local s = make_state("library")
    local out = Nav.ls(s, {"../"})
    T.ok(out:find("Foyer") or out:find("foyer"), "expected Foyer heading")
end)

T.test("ls ../Cellar from library shows cellar files", function()
    local s = make_state("library")
    local out = Nav.ls(s, {"../Cellar"})
    T.ok(out:find("bloody_glove.txt"), "expected cellar files")
end)

-- -----------------------------------------------------------------------
T.suite("pwd / cwd")

T.test("pwd shows path from root", function()
    local s = make_state("library")
    local out = Nav.pwd(s, {})
    T.ok(out:find("library") or out:find("Library"), "expected library in path: " .. out)
end)

T.test("cwd shows previous room path", function()
    local s = make_state("foyer")
    Nav.cd(s, {"Library"})
    local out = Nav.cwd(s, {})
    -- root room renders as "~" in room_path
    T.ok(out == "~" or out:find("foyer") or out:find("Foyer"),
        "expected foyer path as previous: " .. out)
end)
