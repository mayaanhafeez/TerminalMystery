-- test/test_save.lua — save.lua serialization and round-trip behaviour
--
-- save.lua depends on love.filesystem. We stub it with an in-memory table
-- before requiring the module so no LÖVE runtime is needed.

local fake_store = {}

love = {
    filesystem = {
        write   = function(path, content) fake_store[path] = content; return true, nil end,
        read    = function(path) return fake_store[path] end,
        getInfo = function(path) return fake_store[path] and {} or nil end,
        remove  = function(path) fake_store[path] = nil; return true end,
        -- save_state also writes the vim scratch pad (vim.lua) alongside the
        -- save file; the in-memory store is flat, so this is a no-op.
        createDirectory = function() return true end,
    }
}

local T     = require("test.runner")
local Save  = require("save")
local World = require("world")
local Cmds  = require("commands.items")

local FILE = "test_save_tmp.txt"

local function reset()
    for k in pairs(fake_store) do fake_store[k] = nil end
end

-- -----------------------------------------------------------------------
T.suite("has_save / delete_save")

T.test("has_save returns false when nothing saved", function()
    reset()
    T.ok(not Save.has_save(FILE))
end)

T.test("has_save returns true after save_state", function()
    reset()
    Save.save_state(World.new_state(), FILE)
    T.ok(Save.has_save(FILE))
end)

T.test("delete_save removes the file", function()
    reset()
    Save.save_state(World.new_state(), FILE)
    Save.delete_save(FILE)
    T.ok(not Save.has_save(FILE))
end)

T.test("delete_save is safe when no file exists", function()
    reset()
    Save.delete_save(FILE)
    T.ok(true)
end)

-- -----------------------------------------------------------------------
T.suite("load_state edge cases")

T.test("returns nil when file is missing", function()
    reset()
    T.nil_(Save.load_state(FILE))
end)

-- -----------------------------------------------------------------------
T.suite("save / load round-trip — scalar fields")

T.test("current_room survives round-trip", function()
    reset()
    local s = World.new_state()
    s.current_room = "library"
    Save.save_state(s, FILE)
    T.eq(Save.load_state(FILE).current_room, "library")
end)

T.test("previous_room survives round-trip", function()
    reset()
    local s = World.new_state()
    s.previous_room = "study"
    Save.save_state(s, FILE)
    T.eq(Save.load_state(FILE).previous_room, "study")
end)

T.test("command_count survives round-trip", function()
    reset()
    local s = World.new_state()
    s.command_count = 42
    Save.save_state(s, FILE)
    T.eq(Save.load_state(FILE).command_count, 42)
end)

T.test("elapsed survives round-trip", function()
    reset()
    local s = World.new_state()
    s.elapsed = 123.5
    Save.save_state(s, FILE)
    T.eq(Save.load_state(FILE).elapsed, 123.5)
end)

-- -----------------------------------------------------------------------
T.suite("save / load round-trip — table fields")

T.test("visited table survives round-trip", function()
    reset()
    local s = World.new_state()
    s.visited["cellar"]      = true
    s.visited["home_office"] = true
    Save.save_state(s, FILE)
    local loaded = Save.load_state(FILE)
    T.ok(loaded.visited["foyer"],       "foyer should be visited")
    T.ok(loaded.visited["cellar"],      "cellar should be visited")
    T.ok(loaded.visited["home_office"], "home_office should be visited")
end)

T.test("files_read survives round-trip", function()
    reset()
    local s = World.new_state()
    s.files_read["home_office/draft_email.txt"] = true
    Save.save_state(s, FILE)
    T.ok(Save.load_state(FILE).files_read["home_office/draft_email.txt"])
end)

T.test("unlocked grep survives round-trip as true", function()
    reset()
    local s = World.new_state()
    s.unlocked["grep"] = true
    Save.save_state(s, FILE)
    T.ok(Save.load_state(FILE).unlocked["grep"])
end)

T.test("unlocked grep survives round-trip as false", function()
    reset()
    local s = World.new_state()
    s.unlocked["grep"] = false
    Save.save_state(s, FILE)
    T.ok(not Save.load_state(FILE).unlocked["grep"])
end)

T.test("destroyed items survive round-trip", function()
    reset()
    local s = World.new_state()
    s.destroyed["cellar/badge.txt"] = true
    Save.save_state(s, FILE)
    T.ok(Save.load_state(FILE).destroyed["cellar/badge.txt"])
end)

-- -----------------------------------------------------------------------
T.suite("transient field exclusion")

T.test("won is not saved", function()
    reset()
    local s = World.new_state(); s.won = true
    Save.save_state(s, FILE)
    T.nil_(Save.load_state(FILE).won)
end)

T.test("start_time is not saved", function()
    reset()
    local s = World.new_state(); s.start_time = 99999
    Save.save_state(s, FILE)
    T.nil_(Save.load_state(FILE).start_time)
end)

T.test("popup_item is not saved", function()
    reset()
    local s = World.new_state(); s.popup_item = { id = "fake" }
    Save.save_state(s, FILE)
    T.nil_(Save.load_state(FILE).popup_item)
end)

-- -----------------------------------------------------------------------
T.suite("room snapshot")

T.test("visited rooms appear in saved rooms table", function()
    reset()
    local s = World.new_state()
    s.visited["home_office"] = true
    Save.save_state(s, FILE)
    local loaded = Save.load_state(FILE)
    T.ok(loaded.rooms["foyer"],       "foyer should be in saved rooms")
    T.ok(loaded.rooms["home_office"], "home_office should be in saved rooms")
end)

T.test("unvisited rooms are absent from saved rooms table", function()
    reset()
    local s = World.new_state()   -- only foyer visited
    Save.save_state(s, FILE)
    T.nil_(Save.load_state(FILE).rooms["cellar"],      "unvisited cellar should not be saved")
    T.nil_(Save.load_state(FILE).rooms["home_office"], "unvisited home_office should not be saved")
end)

T.test("saved room entry contains items table", function()
    reset()
    local s = World.new_state()   -- foyer visited
    Save.save_state(s, FILE)
    local rooms = Save.load_state(FILE).rooms
    T.ok(type(rooms["foyer"].items) == "table", "foyer entry should have an items table")
end)

-- -----------------------------------------------------------------------
T.suite("save / load round-trip — sed edits (writable + content)")

T.test("sed -i edit and writable flag survive round-trip", function()
    reset()
    local s = World.new_state()
    s.visited["home_office"] = true
    local item = World.rooms.home_office.items["draft_email.txt"]
    item.writable = true
    item.edited   = true
    item.content  = "line with \"quotes\"\nsecond\ttab line"

    Save.save_state(s, FILE)
    World.restore_rooms(Save.load_state(FILE).rooms)

    local r = World.rooms.home_office.items["draft_email.txt"]
    T.eq(r.writable, true)
    T.eq(r.edited, true)
    T.eq(r.content, "line with \"quotes\"\nsecond\ttab line",
        "multi-line content with quotes/tabs must round-trip exactly")
end)

T.test("unedited files do not persist content (rehydrate from registry)", function()
    reset()
    local s = World.new_state()
    s.visited["home_office"] = true
    Save.save_state(s, FILE)
    local stub = Save.load_state(FILE).rooms["home_office"].items["draft_email.txt"]
    T.nil_(stub.content, "unedited file stub should omit content")
end)

-- -----------------------------------------------------------------------
T.suite("save / load round-trip — cp copies")

T.test("a copied file survives a save/load round-trip with its content", function()
    reset()
    local s = World.new_state()
    s.current_room = "home_office"
    s.visited = { foyer = true, home_office = true, cellar = true }
    local original_content = World.rooms.home_office.items["draft_email.txt"].content

    Cmds.cp(s, {"draft_email.txt", "cellar"})
    T.ok(World.rooms.cellar.items["draft_email.txt"], "copy should exist before save")

    Save.save_state(s, FILE)
    -- Wipe rooms to prove the copy comes back from disk, not lingering state.
    World.new_state()
    T.nil_(World.rooms.cellar.items["draft_email.txt"], "copy should be gone after reset")

    World.restore_rooms(Save.load_state(FILE).rooms)
    local copy = World.rooms.cellar.items["draft_email.txt"]
    T.ok(copy, "copy should be restored from the save")
    T.eq(copy.copied, true, "restored copy keeps the copied flag")
    T.eq(copy.content, original_content, "restored copy rehydrates content from registry")
end)

T.test("a renamed copy survives a save/load round-trip", function()
    reset()
    local s = World.new_state()
    s.current_room = "home_office"
    s.visited = { foyer = true, home_office = true }

    Cmds.cp(s, {"draft_email.txt", "backup.txt"})
    Save.save_state(s, FILE)
    World.new_state()
    World.restore_rooms(Save.load_state(FILE).rooms)

    T.ok(World.rooms.home_office.items["backup.txt"], "renamed copy should be restored")
    T.eq(World.rooms.home_office.items["backup.txt"].filename, "backup.txt")
end)
