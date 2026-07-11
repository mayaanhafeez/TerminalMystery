-- test/test_navigation.lua — cd and ls command behaviour

local T = require("test.runner")
local World = require("world")
local Nav = require("commands.navigation")
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
T.suite("cd — basic navigation")

T.test("cd into adjacent room by name", function()
    local s = make_state("foyer")
    Nav.cd(s, {"den"})
    T.eq(s.current_room, "den")
end)

T.test("cd is case-insensitive", function()
    local s = make_state("foyer")
    Nav.cd(s, {"Den"})
    T.eq(s.current_room, "den")
end)

T.test("cd marks room visited", function()
    local s = make_state("foyer")
    Nav.cd(s, {"sunroom"})
    T.ok(s.visited["sunroom"])
end)

T.test("cd updates previous_room", function()
    local s = make_state("foyer")
    Nav.cd(s, {"den"})
    T.eq(s.previous_room, "foyer")
end)

T.test("cd to non-adjacent existing room reports no direct path", function()
    local s = make_state("home_office")
    local out = Nav.cd(s, {"cellar"})
    T.ok(out:find("no direct path") or out:find("No such"), "expected 'no direct path' error, got: " .. out)
    T.eq(s.current_room, "home_office")
end)

T.test("cd to nonexistent room reports error", function()
    local s = make_state("foyer")
    local out = Nav.cd(s, {"Ballroom"})
    T.ok(out:find("No such") or out:find("no such"), "expected error: " .. out)
end)

T.test("cd .. goes to parent", function()
    local s = make_state("home_office", {"home_office", "foyer"})
    Nav.cd(s, {".."}); T.eq(s.current_room, "foyer")
end)

T.test("cd .. from root stays at root", function()
    local s = make_state("foyer")
    Nav.cd(s, {".."}); T.eq(s.current_room, "foyer")
end)

T.test("cd ../Sunroom from home_office reaches sunroom", function()
    local s = make_state("home_office", {"home_office", "foyer"})
    Nav.cd(s, {"../Sunroom"})
    T.eq(s.current_room, "sunroom")
end)

T.test("cd ../Garage marks both intermediate and destination visited", function()
    local s = make_state("home_office", {"home_office"})
    Nav.cd(s, {"../Garage"})
    T.ok(s.visited["foyer"], "foyer should be marked visited")
    T.ok(s.visited["garage"], "garage should be marked visited")
end)

T.test("cd - returns to previous room", function()
    local s = make_state("foyer")
    Nav.cd(s, {"den"})
    Nav.cd(s, {"-"})
    T.eq(s.current_room, "foyer")
end)

T.test("cd with no args goes to root", function()
    local s = make_state("home_office", {"home_office", "foyer"})
    Nav.cd(s, {})
    T.eq(s.current_room, "foyer")
end)

-- -----------------------------------------------------------------------
T.suite("cd — locked room (chmod 000)")

T.test("cd into a mode-000 room is denied", function()
    local s = make_state("foyer")
    -- server_room ships locked (mode = "000")
    local out = Nav.cd(s, {"server_room"})
    T.ok(out:find("denied") or out:find("locked"), "expected permission denied: " .. out)
    T.eq(s.current_room, "foyer")
end)

-- -----------------------------------------------------------------------
T.suite("cd — mv-key gate (Wine Cellar)")

T.test("cd cellar is denied without the keycard present", function()
    local s = make_state("foyer")
    local out = Nav.cd(s, {"cellar"})
    T.ok(out:find("badge") or out:find("lock"), "expected smart-lock message: " .. out)
    T.eq(s.current_room, "foyer")
end)

T.test("cd cellar succeeds after the keycard is moved into the leaving-from room", function()
    local s = make_state("foyer", {"foyer", "sunroom"})
    -- bring the keycard from the Sunroom to the Entrance Hall (current room)
    Items.mv(s, {"Sunroom/keycard.txt", "."})
    local out = Nav.cd(s, {"cellar"})
    T.eq(s.current_room, "cellar")
    T.ok(out:find("Wine Cellar") or out:find("smart lock"), "expected cellar description: " .. out)
end)

-- -----------------------------------------------------------------------
T.suite("ls — room listing")

T.test("ls current room shows files", function()
    local s = make_state("home_office")
    local out = Nav.ls(s, {})
    T.ok(out:find("draft_email.txt"), "expected draft_email.txt in listing")
    T.ok(out:find("repo_log.txt"), "expected repo_log.txt in listing")
end)

T.test("ls shows exits", function()
    local s = make_state("foyer")
    local out = Nav.ls(s, {})
    T.ok(out:find("Den"), "expected Den in exits")
    T.ok(out:find("Sunroom"), "expected Sunroom in exits")
end)

T.test("ls does not show hidden rooms by default", function()
    local s = make_state("den")
    local out = Nav.ls(s, {})
    T.ok(not out:find("closet"), "hidden .closet should not appear without -a")
end)

T.test("ls -a shows hidden rooms", function()
    local s = make_state("den")
    local out = Nav.ls(s, {"-a"})
    T.ok(out:find(".closet"), "expected .closet with -a flag")
end)

T.test("ls does not show hidden files by default", function()
    local s = make_state("home_office")
    local out = Nav.ls(s, {})
    T.ok(not out:find("cipher_note"), "hidden cipher_note should not appear without -a")
end)

T.test("ls -a shows hidden files", function()
    local s = make_state("home_office")
    local out = Nav.ls(s, {"-a"})
    T.ok(out:find("cipher_note.txt"), "expected cipher_note.txt with -a flag")
end)

T.test("ls <path> shows another room", function()
    local s = make_state("foyer")
    local out = Nav.ls(s, {"den"})
    T.ok(out:find("victim.txt"), "expected den files")
end)

T.test("ls ../ from home_office shows the Entrance Hall", function()
    local s = make_state("home_office")
    local out = Nav.ls(s, {"../"})
    T.ok(out:find("Entrance Hall"), "expected Entrance Hall heading")
end)

T.test("ls ../Sunroom from home_office shows sunroom files", function()
    local s = make_state("home_office")
    local out = Nav.ls(s, {"../Sunroom"})
    T.ok(out:find("espresso_bar.txt"), "expected sunroom files")
end)

-- -----------------------------------------------------------------------
T.suite("pwd / cwd")

T.test("pwd shows path from root", function()
    local s = make_state("home_office")
    local out = Nav.pwd(s, {})
    T.ok(out:find("home_office"), "expected home_office in path: " .. out)
end)

T.test("cwd shows previous room path", function()
    local s = make_state("foyer")
    Nav.cd(s, {"den"})
    local out = Nav.cwd(s, {})
    -- root room renders as "~" in room_path
    T.ok(out == "~" or out:find("foyer"), "expected foyer path as previous: " .. out)
end)
