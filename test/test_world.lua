-- test/test_world.lua — world.lua normalization and helpers

local T = require("test.runner")
local World = require("world")

T.suite("Room normalization")

T.test("id is derived from table key", function()
    T.eq(World.rooms.foyer.id, "foyer")
    T.eq(World.rooms.home_office.id, "home_office")
    T.eq(World.rooms[".closet"].id, ".closet")
end)

T.test("name is set explicitly or capitalized id by default", function()
    T.eq(World.rooms.foyer.name, "entrance_hall")
    T.eq(World.rooms.home_office.name, "home_office")
    T.eq(World.rooms.den.name, "the_den")
    T.eq(World.rooms.cellar.name, "wine_cellar")
    T.eq(World.rooms.sunroom.name, "sunroom")
    T.eq(World.rooms.garage.name, "garage")
    T.eq(World.rooms.server_room.name, "server_room")
end)

T.test(".closet name stays lowercase (dot prefix)", function()
    T.eq(World.rooms[".closet"].name, ".closet")
end)

T.test("items are keyed by filename", function()
    T.ok(World.rooms.foyer.items["welcome.txt"], "welcome.txt in foyer")
    T.ok(World.rooms.home_office.items["draft_email.txt"], "draft_email.txt in home_office")
    T.ok(World.rooms.cellar.items["badge.txt"], "badge.txt in cellar")
end)

T.test("item filename override is honored (.log)", function()
    T.ok(World.rooms.server_room.items["audit_stream.log"], "audit_stream.log in server_room")
    T.eq(World.rooms.server_room.items["audit_stream.log"].id, "audit_stream")
end)

T.test("item filename is derived from item key", function()
    T.eq(World.rooms.foyer.items["welcome.txt"].filename, "welcome.txt")
    T.eq(World.rooms.sunroom.items["espresso_bar.txt"].filename, "espresso_bar.txt")
end)

T.test("item room field matches containing room", function()
    T.eq(World.rooms.home_office.items["draft_email.txt"].room, "home_office")
    T.eq(World.rooms.cellar.items["cellar_access_log.txt"].room, "cellar")
end)

T.test("cellar holds exactly two items", function()
    local count = 0
    for _ in pairs(World.rooms.cellar.items) do count = count + 1 end
    T.eq(count, 2)
end)

T.test("parent relationships are correct", function()
    T.eq(World.rooms.home_office.parent, "foyer")
    T.eq(World.rooms.den.parent, "foyer")
    T.eq(World.rooms.sunroom.parent, "foyer")
    T.eq(World.rooms.cellar.parent, "foyer")
    T.eq(World.rooms.garage.parent, "foyer")
    T.eq(World.rooms[".closet"].parent, "den")
    T.nil_(World.rooms.foyer.parent, "foyer has no parent")
end)

T.test("gating fields propagate from raw to rooms", function()
    T.eq(World.rooms.server_room.mode, "000")
    T.eq(World.rooms.server_room.lock_code, "foxglove")
    T.eq(World.rooms.cellar.requires, "keycard.txt")
end)

T.suite("get_item")

T.test("returns item by room + filename", function()
    local item = World.get_item("home_office", "draft_email.txt")
    T.ok(item, "item exists")
    T.eq(item.id, "draft_email")
end)

T.test("returns nil for wrong room", function()
    T.nil_(World.get_item("foyer", "draft_email.txt"))
end)

T.test("returns nil for nonexistent file", function()
    T.nil_(World.get_item("home_office", "nothing.txt"))
end)

T.suite("get_items_in_room")

T.test("returns all non-hidden items", function()
    local items = World.get_items_in_room("den")
    T.eq(#items, 3)
end)

T.test("excludes hidden items by default", function()
    -- game room has slack_grep_help (visible) + office_meme (hidden)
    local items = World.get_items_in_room("game_room")
    T.eq(#items, 1)
end)

T.test("hidden items appear with include_hidden", function()
    local items = World.get_items_in_room("game_room", true)
    T.eq(#items, 2)
end)

T.test("invalid room returns empty list", function()
    local items = World.get_items_in_room("nonexistent")
    T.eq(#items, 0)
end)

T.suite("get_exits")

T.test("foyer has seven children", function()
    local exits = World.get_exits("foyer")
    T.eq(#exits, 7)
end)

T.test("den exit includes foyer (parent) and .closet (child)", function()
    local exits = World.get_exits("den")
    local has_foyer, has_closet = false, false
    for _, id in ipairs(exits) do
        if id == "foyer" then has_foyer = true end
        if id == ".closet" then has_closet = true end
    end
    T.ok(has_foyer, "den exit includes foyer")
    T.ok(has_closet, "den exit includes .closet")
end)

T.test("foyer (root) has no parent", function()
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
    local id = World.resolve_room_path("home_office", ".")
    T.eq(id, "home_office")
end)

T.test(".. resolves to parent", function()
    local id = World.resolve_room_path("home_office", "..")
    T.eq(id, "foyer")
end)

T.test("../Cellar from sunroom resolves to cellar", function()
    local id = World.resolve_room_path("sunroom", "../Cellar")
    T.eq(id, "cellar")
end)

T.test("../home_office from den resolves via parent then child", function()
    local id = World.resolve_room_path("den", "../home_office")
    T.eq(id, "home_office")
end)

T.test("bare Sunroom resolves by name", function()
    local id = World.resolve_room_path("foyer", "Sunroom")
    T.eq(id, "sunroom")
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
