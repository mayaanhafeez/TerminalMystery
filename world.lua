-- world.lua
-- Story, rooms, files, and mutable game state.
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

-- Loose name matching so the player can type "croft" or "dr. croft" etc.
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

-- Map grid uses 3x3 cells. Foyer is the hub; the other four rooms are
-- north / south / east / west of it.
--
--                  Conservatory (2,1)
--   Library (1,2)     Foyer (2,2)    Study (3,2)
--                    Cellar (2,3)

M.rooms = {
	foyer = {
		id = "foyer",
		name = "Foyer",
		parent = nil,
		description = [[The Foyer of Ashworth Manor.

A grand chandelier hangs above polished marble. The mansion's
four wings spread out from this central hall: a Library to the
west, the master's Study to the east, a glass Conservatory
to the north, and the Cellar door open to the south.

A folded note rests on the side table. The guest list lies
beside it, in Lord Ashworth's own hand.]],
	},
	bedroom = {
		id = "bedroom",
		name = "Bedroom",
		parent = "conservatory",
		description = [[Sleeping place]],
	},

	library = {
		id = "library",
		name = "Library",
		parent = "foyer",
		description = [[The Library.

Floor-to-ceiling oak shelves rise to a coffered ceiling. The
fire in the grate has burnt low. A reading chair sits near the
window, beside it a small writing table where someone has
recently been working — a torn sheet of paper lies upon it.]],
	},

	study = {
		id = "study",
		name = "Study",
		parent = "foyer",
		description = [[The Study.

This is where it happened. Lord Ashworth's body has been
covered with a sheet. A brandy glass rests where it fell.
The room smells of pipe tobacco and something sweeter —
something almost floral.

The desk is strewn with papers; a leather diary lies open.]],
	},

	closet = {
		id = ".closet",
		name = ".closet",
		parent = "study",
		hidden = true,
		description = [[A hidden closet behind a bookshelf. {WIP}]],
	},

	conservatory = {
		id = "conservatory",
		name = "Conservatory",
		parent = "foyer",
		description = [[The Conservatory.

A long glasshouse running the length of the manor's north
wing. Lamplight glints off the panes. The air is heavy with
the perfume of orchids and damp earth. A small wrought-iron
table holds the remains of a tea service — and a leather
notebook left open beside it.]],
	},

	cellar = {
		id = "cellar",
		name = "Cellar",
		parent = "foyer",
		description = [[The Cellar.

Cool and dim. The smell of damp stone and old wood. Wine
racks line the walls in long, orderly rows. A barrel sits
in the centre, its lid askew — and something white has been
hastily shoved between it and the wall.]],
	},
}

-- Top-level item list. Each item has:
--   id       unique string key
--   filename the name used with cat/ls/grep
--   content  the full text of the evidence
--   room     which room it belongs to
--   x, y     position in room (0.0–1.0 relative), used by the room view
--   sprite   placeholder key for when real art assets are available
--   removed  set to true if the item is taken / consumed (future use)
M.items = {
	-- Foyer
	{
		id = "welcome",
		filename = "welcome.txt",
		room = "foyer",
		x = 0.30,
		y = 0.35,
		sprite = "scroll",
		removed = false,
		content = [[Dear Investigator,

If you are reading this, the worst has happened. I have left
this note for whoever finds Edmund.

I suspect one of our guests means him harm. I overheard a
quarrel in the Library yesterday — voices raised about money
and a "matter of professional ruin." I dared not enter.

Find the truth. Edmund deserves no less.

— A friend]],
	},
	{
		id = "guest_list",
		filename = "guest_list.txt",
		room = "foyer",
		x = 0.65,
		y = 0.50,
		sprite = "scroll",
		removed = false,
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

	-- Library
	{
		id = "torn_letter",
		filename = "torn_letter.txt",
		room = "library",
		x = 0.35,
		y = 0.60,
		sprite = "scroll",
		removed = false,
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
	{
		id = "bookshelf_log",
		filename = "bookshelf_log.txt",
		room = "library",
		x = 0.70,
		y = 0.35,
		sprite = "book",
		removed = false,
		content = [[Volumes recently borrowed (per the library ledger):

  - "A Treatise on Hellebore and Other Garden Poisons"
  - "The Encyclopaedia of Tropical Maladies"
  - "Reminiscences of the Crimean Campaign"
  - "Modern Methods in Forensic Science"

The first title was signed out by Lady Vivienne Ashworth.
She is, by her own admission, a keen amateur gardener.]],
	},

	-- Study
	{
		id = "victim",
		filename = "victim.txt",
		room = "study",
		x = 0.50,
		y = 0.40,
		sprite = "scroll",
		removed = false,
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
	{
		id = "alibi_notes",
		filename = "alibi_notes.txt",
		room = "study",
		x = 0.25,
		y = 0.65,
		sprite = "scroll",
		removed = false,
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
	{
		id = "desk_diary",
		filename = "desk_diary.txt",
		room = "study",
		x = 0.70,
		y = 0.55,
		sprite = "book",
		removed = false,
		content = [[From Lord Ashworth's desk diary, entry for October 14th:

  "10 pm — R. to call upon me here in the Study. I shall
   give him one last opportunity to confess and put matters
   right before I am compelled to act. I do not relish this.
   He was my dearest friend in Egypt.

   If he refuses, I will have no choice but to write to the
   magistrate in the morning."]],
	},

	-- Conservatory
	{
		id = "tea_service",
		filename = "tea_service.txt",
		room = "conservatory",
		x = 0.40,
		y = 0.45,
		sprite = "scroll",
		removed = false,
		content = [[On the iron table: a porcelain tea set arranged for two.

Both cups have been used. One is empty; the other contains
a finger of cold tea and a curl of lemon peel. The teapot
is half-full and still faintly warm to the touch.

This room was occupied this evening, by at least two people,
despite what the alibis claim.]],
	},
	{
		id = "prescription",
		filename = "prescription.txt",
		room = "conservatory",
		x = 0.68,
		y = 0.65,
		sprite = "scroll",
		removed = false,
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

	-- Cellar
	{
		id = "bloody_glove",
		filename = "bloody_glove.txt",
		room = "cellar",
		x = 0.35,
		y = 0.55,
		sprite = "glove",
		removed = false,
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
	{
		id = "wine_inventory",
		filename = "wine_inventory.txt",
		room = "cellar",
		x = 0.65,
		y = 0.38,
		sprite = "scroll",
		removed = false,
		content = [[Recent withdrawals from the cellar (per the steward's log):

  Oct 12 — 1 bottle Madeira, Lady V.
  Oct 13 — 2 bottles claret, Capt. Blackwood
  Oct 14 — 1 bottle port '97, Capt. Blackwood
  Oct 14 — 1 bottle brandy, Lord E.

The brandy bottle from the 14th cannot be located.]],
	},

	{
		id = "bloody_glove",
		filename = "bloody_glove.txt",
		room = "cellar",
		x = 0.35,
		y = 0.55,
		sprite = "glove",
		removed = false,
		content = [[Tucked behind a barrel of '97 port: a single white surgeon's]],
	},

	{
		id = "clean_sword",
		filename = "clean_sword.txt",
		room = "bedroom",
		x = 0.35,
		y = 0.55,
		sprite = "sword",
		removed = false,
		content = [[A clean sword... almost too clean.]],
	},
}

-- Returns the IDs of rooms directly reachable from room_id (parent + children).
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

-- Returns a list of non-removed items that belong to the given room_id.
-- include_hidden defaults to false; pass true for ls -a behaviour.
function M.get_items_in_room(room_id, include_hidden)
	local result = {}
	for _, item in ipairs(M.items) do
		if item.room == room_id and not item.removed then
			if include_hidden or not item.hidden then
				table.insert(result, item)
			end
		end
	end
	return result
end

-- Returns a single non-removed item matching room_id + filename, or nil.
-- Hidden items are returned when explicitly named (caller knows the filename).
function M.get_item(room_id, filename)
	for _, item in ipairs(M.items) do
		if item.room == room_id and item.filename == filename and not item.removed then
			return item
		end
	end
	return nil
end

-- Build a fresh game state. Called on game start and on replay (R on win).
function M.new_state()
	return {
		current_room = "foyer",
		previous_room = "foyer",
		visited = { foyer = true },
		files_read = {}, -- "room/file" -> true; used to unlock grep
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
		start_time = nil, -- love.timer.getTime() of first real command
		elapsed = 0,
		command_count = 0,
		won = false,
		win_time = nil,
		win_commands = nil,
		popup_item = nil,
	}
end

-- Resolve a file path like "library/torn_letter.txt" or plain "torn_letter.txt".
-- Returns room_id, filename on success, or nil, nil, error_string on failure.
-- "." or "./" is treated as the current room.
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

-- Recompute which gated commands are now available.
function M.check_unlocks(state)
	-- grep unlocks once the player has read two or more pieces of evidence.
	local read_count = 0
	for _ in pairs(state.files_read) do
		read_count = read_count + 1
	end
	if read_count >= 2 then
		state.unlocked.grep = true
	end
end

return M
