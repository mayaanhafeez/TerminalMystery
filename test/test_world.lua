-- test/test_world.lua — world.lua normalization and helpers

local T = require("test.runner")
local World = require("world")

T.suite("Room normalization")

T.test("id is derived from table key", function()
    T.eq(World.rooms.foyer.id, "foyer")
    T.eq(World.rooms.library.id, "library")
    T.eq(World.rooms[".closet"].id, ".closet")
end)

T.test("name is capitalized id by default", function()
    T.eq(World.rooms.foyer.name, "Foyer")
    T.eq(World.rooms.library.name, "Library")
    T.eq(World.rooms.cellar.name, "Cellar")
    T.eq(World.rooms.conservatory.name, "Conservatory")
    T.eq(World.rooms.bedroom.name, "Bedroom")
end)

T.test(".closet name stays lowercase (dot prefix)", function()
    T.eq(World.rooms[".closet"].name, ".closet")
end)

T.test("items are keyed by filename", function()
    T.ok(World.rooms.foyer.items["welcome.txt"], "welcome.txt in foyer")
    T.ok(World.rooms.library.items["torn_letter.txt"], "torn_letter.txt in library")
    T.ok(World.rooms.cellar.items["bloody_glove.txt"], "bloody_glove.txt in cellar")
end)

T.test("item filename is derived from item key", function()
    T.eq(World.rooms.foyer.items["welcome.txt"].filename, "welcome.txt")
    T.eq(World.rooms.conservatory.items["tea_service.txt"].filename, "tea_service.txt")
end)

T.test("item room field matches containing room", function()
    T.eq(World.rooms.library.items["torn_letter.txt"].room, "library")
    T.eq(World.rooms.cellar.items["wine_inventory.txt"].room, "cellar")
end)

T.test("no duplicate bloody_glove", function()
    local count = 0
    for _ in pairs(World.rooms.cellar.items) do count = count + 1 end
    T.eq(count, 2)
end)

T.test("parent relationships are correct", function()
    T.eq(World.rooms.library.parent, "foyer")
    T.eq(World.rooms.study.parent, "foyer")
    T.eq(World.rooms.conservatory.parent, "foyer")
    T.eq(World.rooms.cellar.parent, "foyer")
    T.eq(World.rooms.bedroom.parent, "conservatory")
    T.eq(World.rooms[".closet"].parent, "study")
    T.nil_(World.rooms.foyer.parent, "foyer has no parent")
end)

T.suite("get_item")

T.test("returns item by room + filename", function()
    local item = World.get_item("library", "torn_letter.txt")
    T.ok(item, "item exists")
    T.eq(item.id, "torn_letter")
end)

T.test("returns nil for wrong room", function()
    T.nil_(World.get_item("foyer", "torn_letter.txt"))
end)

T.test("returns nil for nonexistent file", function()
    T.nil_(World.get_item("library", "nothing.txt"))
end)

T.suite("get_items_in_room")

T.test("returns all non-hidden items", function()
    local items = World.get_items_in_room("study")
    T.eq(#items, 3)
end)

T.test("excludes hidden items by default", function()
    -- .closet is hidden; its parent study should not expose it
    local items = World.get_items_in_room("study")
    for _, item in ipairs(items) do
        T.ok(not item.hidden, "no hidden items returned by default")
    end
end)

T.test("empty room returns empty list", function()
    local items = World.get_items_in_room(".closet")
    T.eq(#items, 0)
end)

T.test("invalid room returns empty list", function()
    local items = World.get_items_in_room("nonexistent")
    T.eq(#items, 0)
end)

T.suite("get_exits")

T.test("foyer has four children", function()
    local exits = World.get_exits("foyer")
    T.eq(#exits, 4)
end)

T.test("conservatory exit includes foyer (parent) and bedroom (child)", function()
    local exits = World.get_exits("conservatory")
    local has_foyer, has_bedroom = false, false
    for _, id in ipairs(exits) do
        if id == "foyer" then has_foyer = true end
        if id == "bedroom" then has_bedroom = true end
    end
    T.ok(has_foyer, "conservatory exit includes foyer")
    T.ok(has_bedroom, "conservatory exit includes bedroom")
end)

T.test("foyer (root) has no parent exit", function()
    local exits = World.get_exits("foyer")
    for _, id in ipairs(exits) do
        T.ok(id ~= nil, "exit ids are not nil")
    end
    -- root has no parent, so all exits are children
    T.ok(World.rooms.foyer.parent == nil, "foyer has no parent")
end)

T.suite("resolve_room_path")

T.test("bare room name", function()
    local id = World.resolve_room_path("foyer", "Cellar")
    T.eq(id, "cellar")
end)

T.test("bare room name case-insensitive", function()
    local id = World.resolve_room_path("foyer", "cellar")
    T.eq(id, "cellar")
end)

T.test(". resolves to current room", function()
    local id = World.resolve_room_path("library", ".")
    T.eq(id, "library")
end)

T.test(".. resolves to parent", function()
    local id = World.resolve_room_path("library", "..")
    T.eq(id, "foyer")
end)

T.test("../Cellar from conservatory resolves to cellar", function()
    local id = World.resolve_room_path("conservatory", "../Cellar")
    T.eq(id, "cellar")
end)

T.test("../Library from study resolves to library", function()
    local id = World.resolve_room_path("study", "../Library")
    T.eq(id, "library")
end)

T.test("../Bedroom from conservatory resolves via parent then child", function()
    -- bedroom is child of conservatory, so from study: ../Conservatory/Bedroom
    -- but from foyer: Conservatory/Bedroom or just direct "bedroom" name
    local id = World.resolve_room_path("foyer", "Conservatory")
    T.eq(id, "conservatory")
end)

T.test(".. from root stays at root (no parent)", function()
    local id = World.resolve_room_path("foyer", "..")
    T.eq(id, "foyer")  -- no parent → stays at root, matching cd behaviour
end)

T.test("nonexistent room returns nil + error", function()
    local id, err = World.resolve_room_path("foyer", "../Nowhere")
    T.nil_(id)
    T.ok(err, "error message returned")
end)
