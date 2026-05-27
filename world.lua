-- world.lua
-- Story data and mutable game state.
-- Pure data + small state helpers. Knows nothing about rendering or LÖVE.

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
	["croft"]                    = "Dr. Reginald Croft",
	["dr croft"]                 = "Dr. Reginald Croft",
	["dr. croft"]                = "Dr. Reginald Croft",
	["reginald"]                 = "Dr. Reginald Croft",
	["reginald croft"]           = "Dr. Reginald Croft",
	["dr reginald croft"]        = "Dr. Reginald Croft",
	["dr. reginald croft"]       = "Dr. Reginald Croft",
	["vivienne"]                 = "Lady Vivienne Ashworth",
	["lady vivienne"]            = "Lady Vivienne Ashworth",
	["vivienne ashworth"]        = "Lady Vivienne Ashworth",
	["lady vivienne ashworth"]   = "Lady Vivienne Ashworth",
	["lady ashworth"]            = "Lady Vivienne Ashworth",
	["eliza"]                    = "Miss Eliza Hartwell",
	["hartwell"]                 = "Miss Eliza Hartwell",
	["miss hartwell"]            = "Miss Eliza Hartwell",
	["eliza hartwell"]           = "Miss Eliza Hartwell",
	["miss eliza hartwell"]      = "Miss Eliza Hartwell",
	["theodore"]                 = "Captain Theodore Blackwood",
	["blackwood"]                = "Captain Theodore Blackwood",
	["theodore blackwood"]       = "Captain Theodore Blackwood",
	["captain blackwood"]        = "Captain Theodore Blackwood",
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
		items = {
			welcome = {
				x = 0.30, y = 0.35, sprite = "scroll",
				content = [[Dear Investigator,

If you are reading this, the worst has happened. I have left
this note for whoever finds Edmund.

I suspect one of our guests means him harm. I overheard a
quarrel in the Library yesterday — voices raised about money
and a "matter of professional ruin." I dared not enter.

Find the truth. Edmund deserves no less.

— A friend]],
			},
			guest_list = {
				x = 0.65, y = 0.50, sprite = "scroll",
				content = [[Guests in residence the night of October 14th, 1923:

  Lady Vivienne Ashworth      (wife of the deceased)
  Dr. Reginald Croft          (family physician)
  Miss Eliza Hartwell         (governess to the children)
  Captain Theodore Blackwood  (army comrade of Lord Ashworth)

Staff dismissed for the evening at 8pm by Lord Ashworth's
explicit instruction.

Lord Edmund Ashworth retired to his Study at approximately
9:45 PM. He was found at 10:20 PM by Lady Vivienne.]],
			},
		},
	},

	library = {
		parent = "foyer",
		description = [[The Library.

Floor-to-ceiling oak shelves rise to a coffered ceiling. The
fire in the grate has burnt low. A reading chair sits near the
window, beside it a small writing table where someone has
recently been working — a torn sheet of paper lies upon it.]],
		items = {
			torn_letter = {
				x = 0.35, y = 0.60, sprite = "scroll",
				content = [==[... and I cannot impress upon you strongly enough, Edmund,
the gravity of what I have found. The fund for the medical
treatment of the village children is missing nearly three
hundred pounds. The ledger entries are in R.C.'s hand.

I do not wish to believe it of him. We have known the man
since the war. But the figures do not lie, and I will be
forced to lay this before the magistrate at the end of the
month unless he confesses and makes restitution.

I have asked him to come to me on the evening of the 14th
to settle the matter privately. God grant me the wisdom
[remainder torn away]]==],
			},
			bookshelf_log = {
				x = 0.70, y = 0.35, sprite = "book",
				content = [[Volumes recently borrowed (per the library ledger):

  - "A Treatise on Hellebore and Other Garden Poisons"
  - "The Encyclopaedia of Tropical Maladies"
  - "Reminiscences of the Crimean Campaign"
  - "Modern Methods in Forensic Science"

The first title was signed out by Lady Vivienne Ashworth.
She is, by her own admission, a keen amateur gardener.]],
			},
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
		items = {
			victim = {
				x = 0.50, y = 0.40, sprite = "scroll",
				content = [[Lord Edmund Ashworth, aged 54.

Cause of death (preliminary): cardiac arrest, almost certainly
poisoning. Foam at the mouth. Pupils widely dilated. The
sickly-sweet smell on his breath is consistent with digitalis
toxicity — a derivative of the foxglove plant, used medicinally
in carefully measured doses to slow a racing heart, but lethal
in excess.

On the desk: a half-finished glass of brandy. A small medicine
bottle, empty. The bottle bears no label.

Time of death: between 10:00 and 10:20 PM.]],
			},
			alibi_notes = {
				x = 0.25, y = 0.65, sprite = "scroll",
				content = [[Statements collected immediately after the body was found:

Lady Vivienne Ashworth:
  "I was in the Conservatory tending to my orchids until
   I went to fetch Edmund for our nightly cocoa at 10:20.
   That is when I found him."

Dr. Reginald Croft:
  "I was reading alone in the Library all evening. I heard
   nothing. I came running only when Vivienne cried out."

Miss Eliza Hartwell:
  "I was upstairs in the nursery with the children. They
   are both feverish and I did not leave their bedside."

Captain Theodore Blackwood:
  "I was in the Cellar selecting a bottle of port. Edmund
   keeps — kept — an excellent 1897 down there. I returned
   to the drawing room at about 10:15."]],
			},
			desk_diary = {
				x = 0.70, y = 0.55, sprite = "book",
				content = [[From Lord Ashworth's desk diary, entry for October 14th:

  "10 pm — R. to call upon me here in the Study. I shall
   give him one last opportunity to confess and put matters
   right before I am compelled to act. I do not relish this.
   He was my dearest friend in Egypt.

   If he refuses, I will have no choice but to write to the
   magistrate in the morning."]],
			},
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
		items = {
			tea_service = {
				x = 0.40, y = 0.45, sprite = "scroll",
				content = [[On the iron table: a porcelain tea set arranged for two.

Both cups have been used. One is empty; the other contains
a finger of cold tea and a curl of lemon peel. The teapot
is half-full and still faintly warm to the touch.

This room was occupied this evening, by at least two people,
despite what the alibis claim.]],
			},
			prescription = {
				x = 0.68, y = 0.65, sprite = "scroll",
				content = [[The leather notebook on the table is a physician's
prescription pad. The topmost page reads:

   Patient: Lord E. Ashworth
   Date:    October 14th, 1923

   Rx: Tincture of digitalis, 30 drops in brandy,
       to be taken upon retiring for the night.

       — R. Croft, M.D.

A normal therapeutic dose is two to four drops. Thirty drops
would stop a strong man's heart within minutes.

A torn corner of the same paper has been crumpled and dropped
beneath the table, as if in haste.]],
			},
		},
	},

	cellar = {
		parent = "foyer",
		description = [[The Cellar.

Cool and dim. The smell of damp stone and old wood. Wine
racks line the walls in long, orderly rows. A barrel sits
in the centre, its lid askew — and something white has been
hastily shoved between it and the wall.]],
		items = {
			bloody_glove = {
				x = 0.35, y = 0.55, sprite = "glove",
				content = [[Tucked behind a barrel of '97 port: a single white surgeon's
glove, balled up and damp. The cotton is stained dark brown
along the thumb and forefinger — the colour of dried blood,
or perhaps something else.

The silk lining bears a monogram embroidered in fine red
thread:

       R. C.

A second glove is not in evidence. Whoever wore it was here
this evening, and was in a hurry.]],
			},
			wine_inventory = {
				x = 0.65, y = 0.38, sprite = "scroll",
				content = [[Recent withdrawals from the cellar (per the steward's log):

  Oct 12 — 1 bottle Madeira, Lady V.
  Oct 13 — 2 bottles claret, Capt. Blackwood
  Oct 14 — 1 bottle port '97, Capt. Blackwood
  Oct 14 — 1 bottle brandy, Lord E.

The brandy bottle from the 14th cannot be located.]],
			},
		},
	},

	bedroom = {
		parent = "conservatory",
		description = [[Sleeping place]],
		items = {
			clean_sword = {
				x = 0.35, y = 0.55, sprite = "sword",
				content = [[A clean sword... almost too clean.]],
			},
		},
	},
}

-- Normalize raw definitions into M.rooms.
-- Each room gets: id, name, parent, hidden, description, items (keyed by filename).
-- Each item gets: id, filename, room, plus any fields from the definition.
M.rooms = {}
for id, def in pairs(raw) do
	local room = {
		id          = id,
		name        = def.name or (id:sub(1, 1):upper() .. id:sub(2)),
		parent      = def.parent,
		hidden      = def.hidden,
		description = def.description,
		items       = {},
	}
	for item_id, item_def in pairs(def.items or {}) do
		local item = {}
		for k, v in pairs(item_def) do item[k] = v end
		item.id       = item_id
		item.filename = item_def.filename or (item_id .. ".txt")
		item.room     = id
		room.items[item.filename] = item
	end
	M.rooms[id] = room
end

-- Returns the IDs of rooms directly reachable from room_id (parent + children).
function M.get_exits(room_id)
	local exits = {}
	local parent = M.rooms[room_id].parent
	if parent then table.insert(exits, parent) end
	for id, r in pairs(M.rooms) do
		if r.parent == room_id then table.insert(exits, id) end
	end
	return exits
end

-- Returns a list of items in the given room.
-- include_hidden: when false, skips items with hidden = true.
function M.get_items_in_room(room_id, include_hidden)
	local room = M.rooms[room_id]
	if not room then return {} end
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
						found = id; break
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
	for _ in pairs(state.files_read) do read_count = read_count + 1 end
	if read_count >= 2 then state.unlocked.grep = true end
end

-- Build a fresh game state.
function M.new_state()
	return {
		current_room  = "foyer",
		previous_room = "foyer",
		visited       = { foyer = true },
		files_read    = {},
		unlocked      = {
			cd     = true,
			ls     = true,
			echo   = true,
			help   = true,
			pwd    = true,
			cwd    = true,
			exit   = true,
			accuse = true,
			cat    = true,
			grep   = false,
			find   = true,
			diff   = true,
			rm     = true,
			cp     = true,
			mv     = true,
			chmod  = true,
		},
		destroyed     = {},
		start_time    = nil,
		elapsed       = 0,
		command_count = 0,
		won           = false,
		win_time      = nil,
		win_commands  = nil,
		popup_item    = nil,
	}
end

return M
