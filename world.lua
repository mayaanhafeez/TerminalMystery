-- world.lua
-- Story data and mutable game state.
-- Pure data + small state helpers. Knows nothing about rendering or LÖVE.

local Items = require("items")

local M = {}

M.title = "Ashworth Manor — October 14th, 1923"

M.suspects = {
	"Lady Vivienne Ashworth",
	"Dr. Reginald Croft",
	"Miss Eliza Hartwell",
	"Captain Theodore Blackwood",
}

M.murderer = "Dr. Reginald Croft"

M.accuse_aliases = {
	["croft"] = "Dr. Reginald Croft",
	["dr croft"] = "Dr. Reginald Croft",
	["dr. croft"] = "Dr. Reginald Croft",
	["reginald"] = "Dr. Reginald Croft",
	["reginald croft"] = "Dr. Reginald Croft",
	["dr reginald croft"] = "Dr. Reginald Croft",
	["dr. reginald croft"] = "Dr. Reginald Croft",
	["vivienne"] = "Lady Vivienne Ashworth",
	["lady vivienne"] = "Lady Vivienne Ashworth",
	["vivienne ashworth"] = "Lady Vivienne Ashworth",
	["lady vivienne ashworth"] = "Lady Vivienne Ashworth",
	["lady ashworth"] = "Lady Vivienne Ashworth",
	["eliza"] = "Miss Eliza Hartwell",
	["hartwell"] = "Miss Eliza Hartwell",
	["miss hartwell"] = "Miss Eliza Hartwell",
	["eliza hartwell"] = "Miss Eliza Hartwell",
	["miss eliza hartwell"] = "Miss Eliza Hartwell",
	["theodore"] = "Captain Theodore Blackwood",
	["blackwood"] = "Captain Theodore Blackwood",
	["theodore blackwood"] = "Captain Theodore Blackwood",
	["captain blackwood"] = "Captain Theodore Blackwood",
	["captain theodore blackwood"] = "Captain Theodore Blackwood",
}

-- Room definitions with inline items.
-- Derived automatically unless overridden:
--   room id   → the table key
--   room name → capitalize first letter of id  (e.g. "foyer" → "Foyer")
--   item filename → id .. ".txt"             (e.g. "torn_letter" → "torn_letter.txt")
local raw = {
	foyer = {
		description = [[The Foyer of Ashworth Manor.

A grand chandelier hangs above polished marble. The mansion's
four wings spread out from this central hall: a Library to the
west, the master's Study to the east, a glass Conservatory
to the north, and the Cellar door open to the south.

A folded note rests on the side table. The guest list lies
beside it, in Lord Ashworth's own hand.]],
		wall = { 0.34, 0.30, 0.22 },
		floor = { 0.72, 0.66, 0.50 },
		floor_tint = { 0.88, 0.80, 0.58, 0.20 },
		furniture = {
			{ "dresser_flower", 0.10, 150 },
			{ "clock", 0.48, 72 },
			{ "mirror", 0.72, 215 },
		},
		items = {
			{ ref = "welcome", x = 0.30, y = 0.35 },
			{ ref = "guest_list", x = 0.65, y = 0.50 },
		},
    tiles = {
      legend = {
        ["F"] = "assets/sprites/floor/foyer.png",
        ["W"] = "assets/sprites/floor/library.png",
      },
      layers = {
        {
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "WWWWWWWWWWWW",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        "FFFFFFFFFFFF",
        }
    },
	},

	library = {
		parent = "foyer",
		description = [[The Library.

Floor-to-ceiling oak shelves rise to a coffered ceiling. The
fire in the grate has burnt low. A reading chair sits near the
window, beside it a small writing table where someone has
recently been working — a torn sheet of paper lies upon it.]],
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
			{ ref = "torn_letter", x = 0.35, y = 0.60 },
			{ ref = "bookshelf_log", x = 0.70, y = 0.35 },
		},
	},

	study = {
		parent = "foyer",
		description = [[The Study.

This is where it happened. Lord Ashworth's body has been
covered with a sheet. A brandy glass rests where it fell.
The room smells of pipe tobacco and something sweeter —
something almost floral.

The desk is strewn with papers; a leather diary lies open.]],
		wall = { 0.16, 0.14, 0.18 },
		floor = { 0.36, 0.30, 0.26 },
		floor_tint = { 0.20, 0.14, 0.26, 0.35 },
		furniture = {
			{ "mirror", 0.28, 215 },
			{ "dresser", 0.82, 150 },
		},
		items = {
			{ ref = "victim", x = 0.50, y = 0.40 },
			{ ref = "alibi_notes", x = 0.25, y = 0.65 },
			{ ref = "desk_diary", x = 0.70, y = 0.55 },
		},
	},

	[".closet"] = {
		parent = "study",
		hidden = true,
		description = [[A hidden closet behind a bookshelf. {WIP}]],
		items = {},
	},

	conservatory = {
		parent = "foyer",
		description = [[The Conservatory.

A long glasshouse running the length of the manor's north
wing. Lamplight glints off the panes. The air is heavy with
the perfume of orchids and damp earth. A small wrought-iron
table holds the remains of a tea service — and a leather
notebook left open beside it.]],
		wall = { 0.12, 0.22, 0.20 },
		floor = { 0.46, 0.50, 0.40 },
		floor_tint = { 0.14, 0.32, 0.28, 0.30 },
		furniture = {
			{ "dresser_flower", 0.10, 140 },
			{ "clock", 0.50, 72 },
			{ "painting", 0.88, 82 },
		},
		items = {
			{ ref = "tea_service", x = 0.40, y = 0.45 },
			{ ref = "prescription", x = 0.68, y = 0.65 },
		},
	},

	cellar = {
		parent = "foyer",
		description = [[The Cellar.

Cool and dim. The smell of damp stone and old wood. Wine
racks line the walls in long, orderly rows. A barrel sits
in the centre, its lid askew — and something white has been
hastily shoved between it and the wall.]],
		wall = { 0.09, 0.08, 0.09 },
		floor = { 0.20, 0.18, 0.16 },
		floor_tint = { 0.02, 0.02, 0.03, 0.75 },
		furniture = {
			{ "armoire", 0.50, 170 },
		},
		items = {
			{ ref = "bloody_glove", x = 0.35, y = 0.55 },
			{ ref = "wine_inventory", x = 0.65, y = 0.38 },
		},
	},

	bedroom = {
		parent = "conservatory",
		description = [[Sleeping place]],
		floor_tint = { 0.78, 0.55, 0.30, 0.25 },
		rug = true,
		furniture = {
			{ "dresser_flower", 0.10, 150 },
			{ "mirror", 0.70, 215 },
		},
		items = {
			{ ref = "clean_sword", x = 0.35, y = 0.55 },
		},
	},
}
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

-- Resolve a file path like "library/torn_letter.txt" or plain "torn_letter.txt".
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
            room.items[filename] = item
        end
      end
    end
  end
end

return M
