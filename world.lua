-- world.lua
-- Story data and mutable game state.
-- Pure data + small state helpers. Knows nothing about rendering or LÖVE.

local Items = require("items")

local M = {}

M.title = "Strictly.ai — Series C Launch, Oct 14"

M.suspects = {
	"Ayesha Raza",
	"Wei Zhao",
	"Priya Raghavan",
	"Daniel Lin",
}

M.murderer = "Daniel Lin"

M.accuse_aliases = {
	["lin"] = "Daniel Lin",
	["daniel"] = "Daniel Lin",
	["daniel lin"] = "Daniel Lin",
	["dlin"] = "Daniel Lin",
	["ayesha"] = "Ayesha Raza",
	["raza"] = "Ayesha Raza",
	["ayesha raza"] = "Ayesha Raza",
	["araza"] = "Ayesha Raza",
	["wei"] = "Wei Zhao",
	["zhao"] = "Wei Zhao",
	["wei zhao"] = "Wei Zhao",
	["wzhao"] = "Wei Zhao",
	["priya"] = "Priya Raghavan",
	["raghavan"] = "Priya Raghavan",
	["priya raghavan"] = "Priya Raghavan",
	["praghavan"] = "Priya Raghavan",
}

-- Room definitions with inline items.
-- Derived automatically unless overridden:
--   room id   → the table key
--   room name → capitalize first letter of id  (e.g. "foyer" → "Foyer")
--   item filename → id .. ".txt"             (e.g. "guest_list" → "guest_list.txt")
local raw = {
	foyer = {
		name = "Entrance Hall",
		description = [[The Entrance Hall of Trent Kessler's house in the hills.

Series C banners still hang from the balcony. Half the
engineering org is somewhere in here or the rooms beyond:
a Home Office to one side, the Den where Arjun was found,
a Sunroom, the Garage, a Game Room, the Server Room, and the
Wine Cellar down the stairs.

A note has been left on the entry table, weighed down by the
printed guest list. A laptop sits open beside them, still
logged into Slack.]],
		wall = { 0.34, 0.30, 0.22 },
		floor = { 0.72, 0.66, 0.50 },
		floor_tint = { 0.88, 0.80, 0.58, 0.20 },
		furniture = {
			{ "dresser_flower", 0.10, 150 },
			{ "clock", 0.48, 72 },
			{ "mirror", 0.72, 215 },
		},
		items = {
			{ ref = "welcome", x = 0.22, y = 0.30 },
			{ ref = "guest_list", x = 0.55, y = 0.45 },
			{ ref = "slack_general", x = 0.82, y = 0.62 },
		},
    tiles = {
      legend = {
        ["F"] = "assets/foyer-floor.png",
        ["D"] = {path = "assets/foyer-door.png", w =2, h =1},
        ["W"] = "assets/foyer-wall.png",
      },
      layers = {
        {
        "FFFFFF",
        "FFFFFF",
        "FFFFFF",
        "FFFFFF",
        "FFFFFF",
        "FFFFFF",
        "FFFFFF",
        "FFFFFF",
        "FFFFFF",
        },
        {
        "......",
        "......",
        "......",
        "......",
        "......",
        "......",
        "......",
        "......",
        "WWWWWW",
        },
        {
        "......",
        "......",
        "......",
        "......",
        "......",
        "......",
        "......",
        "......",
        "..D...",
        },
    },
	},
	},

	home_office = {
		parent = "foyer",
		name = "Home Office",
		description = [[The Home Office.

Trent's personal workspace — a standing desk, a wall of monitors,
a beanbag in the corner. Daniel says he was in here alone all
night, "grinding a Balatro run."

A desktop is still awake, an unsent email glowing on the screen.
A terminal window shows a list of recently-cloned repos.]],
		wall = { 0.12, 0.16, 0.10 },
		floor = { 0.28, 0.22, 0.14 },
		floor_tint = { 0.04, 0.16, 0.04, 0.50 },
		rug = true,
		furniture = {
			{ "shelf_full", 0.14, 205 },
			{ "painting", 0.50, 82 },
			{ "shelf_empty", 0.86, 205 },
		},
		items = {
			{ ref = "draft_email", x = 0.35, y = 0.55 },
			{ ref = "repo_log", x = 0.70, y = 0.35 },
			{ ref = "cipher_note", x = 0.55, y = 0.72 },
		},
	},

	den = {
		parent = "foyer",
		name = "The Den",
		description = [[The Den. This is where it happened.

A home theater, deep couches, the remains of the launch demo
still on the big screen. Arjun Mehta's body has been covered.
A half-finished bottle of kombucha sits on the side table.

The AV rack hums against the back wall. Behind it, the door to
a service closet stands very slightly ajar.]],
		wall = { 0.16, 0.14, 0.18 },
		floor = { 0.36, 0.30, 0.26 },
		floor_tint = { 0.20, 0.14, 0.26, 0.35 },
		furniture = {
			{ "mirror", 0.28, 215 },
			{ "dresser", 0.82, 150 },
		},
		items = {
			{ ref = "victim", x = 0.50, y = 0.40 },
			{ ref = "party_statements", x = 0.25, y = 0.65 },
			{ ref = "calendar_note", x = 0.70, y = 0.60 },
		},
	},

	[".closet"] = {
		parent = "den",
		hidden = true,
		description = [[A cramped AV / network closet behind the home-theater rack.

Cable spaghetti, a patch panel, and a wastebasket. Something
was crumpled up and dropped in the corner in a hurry.]],
		items = {
			{ ref = "draft_email_continued", x = 0.50, y = 0.50 },
		},
	},

	sunroom = {
		parent = "foyer",
		name = "Sunroom",
		description = [[The Sunroom.

Glass on three sides, string lights, and a very expensive
espresso bar someone set up for the party. Two used cups sit
in the drip tray.

A spare guest badge has been left on the counter.]],
		wall = { 0.12, 0.22, 0.20 },
		floor = { 0.46, 0.50, 0.40 },
		floor_tint = { 0.14, 0.32, 0.28, 0.30 },
		furniture = {
			{ "dresser_flower", 0.10, 140 },
			{ "clock", 0.50, 72 },
			{ "painting", 0.88, 82 },
		},
		items = {
			{ ref = "espresso_bar", x = 0.38, y = 0.45 },
			{ ref = "keycard", x = 0.68, y = 0.62 },
		},
	},

	cellar = {
		parent = "foyer",
		name = "Wine Cellar",
		requires = "keycard.txt",
		description = [[The Wine Cellar, down a flight of stairs.

Cool and dim, racks of bottles in orderly rows. The smart lock
on the door has been finicky all night. Something small and
white is wedged face-down between two of the racks.]],
		wall = { 0.09, 0.08, 0.09 },
		floor = { 0.20, 0.18, 0.16 },
		floor_tint = { 0.02, 0.02, 0.03, 0.75 },
		furniture = {
			{ "armoire", 0.50, 170 },
		},
		items = {
			{ ref = "badge", x = 0.35, y = 0.55 },
			{ ref = "cellar_access_log", x = 0.65, y = 0.38 },
		},
	},

	garage = {
		parent = "foyer",
		name = "Garage",
		description = [[The Garage.

Converted into an overflow workspace: a folding table, a
mechanical keyboard, three monitors on a laptop stand, and a
half-drunk energy drink. Priya was out here most of the night
pushing a hotfix.

A GitHub Actions run history is still up on the screen.]],
		floor_tint = { 0.78, 0.55, 0.30, 0.25 },
		rug = true,
		furniture = {
			{ "dresser_flower", 0.10, 150 },
			{ "mirror", 0.70, 215 },
		},
		items = {
			{ ref = "deploy_log", x = 0.45, y = 0.55 },
		},
	},

	game_room = {
		parent = "foyer",
		name = "Game Room",
		description = [[The Game Room.

A stand-up arcade cabinet, a couch, and a laptop someone left
running a Balatro seed. The office's Balatro obsession clearly
has a home base.

A printout is pinned to the side of the cabinet.]],
		wall = { 0.14, 0.12, 0.20 },
		floor = { 0.30, 0.26, 0.34 },
		floor_tint = { 0.20, 0.10, 0.30, 0.30 },
		furniture = {
			{ "clock", 0.18, 72 },
			{ "painting", 0.52, 82 },
			{ "mirror", 0.84, 215 },
		},
		items = {
			{ ref = "office_meme", x = 0.50, y = 0.55 },
		},
	},

	server_room = {
		parent = "foyer",
		name = "Server Room",
		mode = "000",
		lock_code = "foxglove",
		description = [[The Server Room.

The house's real infrastructure lives here: two racks, blinking
LEDs, a wall of cold air. This is Daniel's domain, and the door
is on a keypad, not a badge.

A workstation in the corner holds a cost report, a personal
spreadsheet, and a raw access log.]],
		wall = { 0.10, 0.12, 0.14 },
		floor = { 0.16, 0.18, 0.20 },
		floor_tint = { 0.10, 0.14, 0.20, 0.45 },
		furniture = {
			{ "armoire", 0.20, 170 },
			{ "shelf_empty", 0.80, 205 },
		},
		items = {
			{ ref = "billing_audit", x = 0.24, y = 0.42 },
			{ ref = "dosage_log", x = 0.50, y = 0.60 },
			{ ref = "slack_final", x = 0.74, y = 0.40 },
			{ ref = "slack_draft", x = 0.74, y = 0.70 },
			{ ref = "audit_stream", x = 0.40, y = 0.80 },
		},
	},
}
-- Normalize raw definitions into M.rooms.
-- Each room gets: id, name, parent, hidden, description, items (keyed by filename).
-- Each item gets: id, filename, room, plus any fields from the definition.
local function build_rooms()
  M.rooms = {}
  for id, def in pairs(raw) do
    local room = {
      id = id,
      tiles = def.tiles,
      name = def.name or (id:sub(1, 1):upper() .. id:sub(2)),
      parent = def.parent,
      hidden = def.hidden,
      description = def.description,
      wall = def.wall,
      floor = def.floor,
      floor_tint = def.floor_tint,
      rug = def.rug,
      furniture = def.furniture,
      mode = def.mode,
      lock_code = def.lock_code,
      requires = def.requires,
      items = {},
    }
    for _, placement in ipairs(def.items or {}) do
      local reg = Items.registry[placement.ref]
      if reg then
        local item = {}
        for k, v in pairs(reg) do
          item[k] = v
        end
        item.id = placement.ref
        item.filename = reg.filename or (placement.ref .. ".txt")
        item.x = placement.x
        item.y = placement.y
        item.room = id
        room.items[item.filename] = item
      end
    end
    M.rooms[id] = room
  end
end
-- Returns the IDs of rooms directly reachable from room_id (parent + children).
build_rooms()

function M.get_exits(room_id)
	local exits = {}
	local parent = M.rooms[room_id].parent
	if parent then
		table.insert(exits, parent)
	end
	for id, r in pairs(M.rooms) do
		if r.parent == room_id then
			table.insert(exits, id)
		end
	end
	return exits
end

-- Returns a list of items in the given room.
-- include_hidden: when false, skips items with hidden = true.
function M.get_items_in_room(room_id, include_hidden)
	local room = M.rooms[room_id]
	if not room then
		return {}
	end
	local result = {}
	for _, item in pairs(room.items) do
		if include_hidden or not item.hidden then
			table.insert(result, item)
		end
	end
	return result
end

-- Returns a single item matching room_id + filename, or nil.
function M.get_item(room_id, filename)
	local room = M.rooms[room_id]
	return room and room.items[filename]
end

-- Resolve a file path like "home_office/draft_email.txt" or plain "draft_email.txt".
-- Returns room_id, filename on success, or nil, nil, error_string on failure.
function M.resolve_file_path(current_room_id, path_str)
	if not path_str:find("/", 1, true) then
		return current_room_id, path_str
	end
	local room_part, file_part = path_str:match("^([^/]+)/(.*)$")
	if not room_part then
		return nil, nil, "invalid path: " .. path_str
	end
	if room_part == "." then
		return current_room_id, (file_part ~= "" and file_part or nil)
	end
	local rp_lower = room_part:lower()
	for id, r in pairs(M.rooms) do
		if id == rp_lower or r.name:lower() == rp_lower then
			return id, (file_part ~= "" and file_part or nil)
		end
	end
	return nil, nil, room_part .. ": no such room"
end

-- Resolve a room path like "../Cellar", "..", ".", or a bare room name.
-- Returns room_id on success, or nil + error string on failure.
-- Does NOT check visited — callers enforce that game mechanic.
function M.resolve_room_path(current_room_id, path_str)
	local segments = {}
	for seg in path_str:gmatch("[^/]+") do
		table.insert(segments, seg)
	end

	if #segments > 0 and (segments[1] == "." or segments[1] == "..") then
		local room_id = current_room_id
		for _, seg in ipairs(segments) do
			if seg == "." then
				-- no-op
			elseif seg == ".." then
				room_id = (M.rooms[room_id] and M.rooms[room_id].parent) or room_id
			else
				local seg_lower = seg:lower()
				local found
				for id, r in pairs(M.rooms) do
					if r.parent == room_id and (id == seg_lower or r.name:lower() == seg_lower) then
						found = id
						break
					end
				end
				if not found then
					return nil, seg .. ": no such room"
				end
				room_id = found
			end
		end
		return room_id
	end

	local name_lower = path_str:lower():match("^(.-)/?$")
	for id, r in pairs(M.rooms) do
		if id == name_lower or r.name:lower() == name_lower then
			return id
		end
	end
	return nil, path_str .. ": no such room"
end

-- Recompute which gated commands are now available.
function M.check_unlocks(state)
	local read_count = 0
	for _ in pairs(state.files_read) do
		read_count = read_count + 1
	end
	if read_count >= 2 then
		state.unlocked.grep = true
	end
end

-- Build a fresh game state.
function M.new_state()
  build_rooms()
	return {
		current_room = "foyer",
		previous_room = "foyer",
		visited = { foyer = true },
		files_read = {},
		unlocked = {
			cd = true,
			ls = true,
			echo = true,
			help = true,
			pwd = true,
			cwd = true,
			exit = true,
			accuse = true,
			cat = true,
			grep = false,
			find = true,
			diff = true,
			rm = true,
			cp = true,
			mv = true,
			chmod = true,
			sed = true,
		},
		destroyed = {},
		start_time = nil,
		elapsed = 0,
		command_count = 0,
		won = false,
		win_time = nil,
		win_commands = nil,
		popup_item = nil,
	}
end

function M.restore_rooms(saved_rooms)
  if not saved_rooms then return end
  for room_id, saved_room in pairs(saved_rooms) do
    local room = M.rooms[room_id]
    if room then
      room.items = {}
      if saved_room.mode then room.mode = saved_room.mode end
      for filename, stub in pairs(saved_room.items) do
        local reg = Items.registry[stub.id]
        if reg then
          local item = {}
          for k, v in pairs(reg) do item[k] = v end
            item.id = stub.id
            item.filename = filename
            item.room = stub.room
            item.copied = stub.copied
            item.x = stub.x
            item.y = stub.y
            item.writable = stub.writable
            item.edited = stub.edited
            -- Restore a sed-edited body; unedited files keep the registry content.
            if stub.content ~= nil then item.content = stub.content end
            room.items[filename] = item
        end
      end
    end
  end
end

return M
