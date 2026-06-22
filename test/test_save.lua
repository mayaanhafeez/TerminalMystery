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
    }
}

local T     = require("test.runner")
local Save  = require("save")
local World = require("world")

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
    s.visited["cellar"]  = true
    s.visited["library"] = true
    Save.save_state(s, FILE)
    local loaded = Save.load_state(FILE)
    T.ok(loaded.visited["foyer"],   "foyer should be visited")
    T.ok(loaded.visited["cellar"],  "cellar should be visited")
    T.ok(loaded.visited["library"], "library should be visited")
end)

T.test("files_read survives round-trip", function()
    reset()
    local s = World.new_state()
    s.files_read["library/torn_letter.txt"] = true
    Save.save_state(s, FILE)
    T.ok(Save.load_state(FILE).files_read["library/torn_letter.txt"])
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
    s.destroyed["cellar/bloody_glove.txt"] = true
    Save.save_state(s, FILE)
    T.ok(Save.load_state(FILE).destroyed["cellar/bloody_glove.txt"])
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
    s.visited["library"] = true
    Save.save_state(s, FILE)
    local loaded = Save.load_state(FILE)
    T.ok(loaded.rooms["foyer"],   "foyer should be in saved rooms")
    T.ok(loaded.rooms["library"], "library should be in saved rooms")
end)

T.test("unvisited rooms are absent from saved rooms table", function()
    reset()
    local s = World.new_state()   -- only foyer visited
    Save.save_state(s, FILE)
    T.nil_(Save.load_state(FILE).rooms["cellar"],  "unvisited cellar should not be saved")
    T.nil_(Save.load_state(FILE).rooms["library"], "unvisited library should not be saved")
end)

T.test("saved room entry contains items table", function()
    reset()
    local s = World.new_state()   -- foyer visited
    Save.save_state(s, FILE)
    local rooms = Save.load_state(FILE).rooms
    T.ok(type(rooms["foyer"].items) == "table", "foyer entry should have an items table")
end)
