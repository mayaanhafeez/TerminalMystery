-- items.lua
-- Intrinsic item definitions (sprite, content). Placement data (x, y, room) lives in world.lua.

local M = {}

M.registry = {

	welcome = {
		sprite  = "scroll",
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
		sprite  = "scroll",
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

	torn_letter = {
		sprite  = "scroll",
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
		sprite  = "book",
		content = [[Volumes recently borrowed (per the library ledger):

  - "A Treatise on Hellebore and Other Garden Poisons"
  - "The Encyclopaedia of Tropical Maladies"
  - "Reminiscences of the Crimean Campaign"
  - "Modern Methods in Forensic Science"

The first title was signed out by Lady Vivienne Ashworth.
She is, by her own admission, a keen amateur gardener.]],
	},

	victim = {
		sprite  = "scroll",
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
		sprite  = "scroll",
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
		sprite  = "book",
		content = [[From Lord Ashworth's desk diary, entry for October 14th:

  "10 pm — R. to call upon me here in the Study. I shall
   give him one last opportunity to confess and put matters
   right before I am compelled to act. I do not relish this.
   He was my dearest friend in Egypt.

   If he refuses, I will have no choice but to write to the
   magistrate in the morning."]],
	},

	tea_service = {
		sprite  = "scroll",
		content = [[On the iron table: a porcelain tea set arranged for two.

Both cups have been used. One is empty; the other contains
a finger of cold tea and a curl of lemon peel. The teapot
is half-full and still faintly warm to the touch.

This room was occupied this evening, by at least two people,
despite what the alibis claim.]],
	},

	prescription = {
		sprite  = "scroll",
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

	bloody_glove = {
		sprite  = "glove",
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
		sprite  = "scroll",
		content = [[Recent withdrawals from the cellar (per the steward's log):

  Oct 12 — 1 bottle Madeira, Lady V.
  Oct 13 — 2 bottles claret, Capt. Blackwood
  Oct 14 — 1 bottle port '97, Capt. Blackwood
  Oct 14 — 1 bottle brandy, Lord E.

The brandy bottle from the 14th cannot be located.]],
	},

	clean_sword = {
		sprite  = "sword",
		content = [[A clean sword... almost too clean.]],
	},

}

return M
