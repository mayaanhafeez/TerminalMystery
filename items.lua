-- items.lua
-- Intrinsic item definitions (sprite, content). Placement data (x, y, room) lives in world.lua.
--
-- Fields:
--   sprite   room-view floor icon key (see render.lua M.sprites)
--   popup    optional popup style override ("slack"); defaults to sprite
--   channel  optional Slack channel / DM label (slack popup only)
--   hidden   requires `ls -a` / grep -a to see
--   filename optional filename override (defaults to id .. ".txt")

local M = {}

M.registry = {

	-- ---------------- Entrance Hall ----------------

	welcome = {
		sprite  = "scroll",
		content = [[To whoever picks this up —

Legal wants this contained before anyone calls the police.
The full guest list is on the entry table. Arjun is in the Den.

Find out what happened tonight, quietly, and come to me first.

— T.K.]],
	},

	guest_list = {
		sprite  = "scroll",
		popup   = "laptop",
		content = [[Strictly.ai — Series C Launch Party
Guest manifest, October 14th:

  Ayesha Raza     — Principal Engineer
  Wei Zhao        — Staff Engineer
  Priya Raghavan  — Senior Systems Engineer
  Daniel Lin      — Head of Infrastructure

Catering staff dismissed at 9:00 PM per contract. Arjun Mehta
(VP, AI Research) last seen heading to the Den around 9:55 PM.

(A fuller personnel file is on the laptop, if you can find it.)]],
	},

	personnel_dossier = {
		sprite  = "laptop",
		popup   = "laptop",
		hidden  = true,
		content = [[=== STRICTLY.AI — CONFIDENTIAL PERSONNEL FILE ===
        Internal use only. Do not distribute.

Network handles are first-initial + last name.

----------------------------------------------------------
AYESHA RAZA   (araza)
  Principal Engineer. Emacs since her PhD and very online
  about it; runs the internal #balatro channel. Was passed
  over for the Staff promotion that went to Arjun. No LSP,
  no auto-correct, no syntax highlighting trad coder."

WEI ZHAO   (wzhao)
  Staff Engineer. Uses Vim btw, currently #1 on the office
  Balatro leaderboard (5.80e2000 on black deck). Had access
  to the Den earlier to fix the AV rig for Trent's demo.

PRIYA RAGHAVAN   (praghavan)
  Senior Systems Engineer. Rewrites to Rust, anti-Jess.
  Deep into supplement stacks; keeps a personal
  creatine-cycle repo.

DANIEL LIN   (dlin)
  Head of Infrastructure. Uses Cursor, Hasn't written a line
  of code since GPT-4o. Quiet; stays out of every editor
  and language fight. Reportedly "grinding a Balatro run
  trying to beat Wei's record." at the time of the murder.
  Holds full admin over billing and provisioning (dlin-admin).

----------------------------------------------------------

Victim: Arjun Mehta (amehta), VP of AI Research and the
internal face of JessAI. Ex-Emacs user. Python. Last
seen heading to the Den at about 9:55 PM.]],

	},

	slack_general = {
		sprite  = "laptop",
		popup   = "slack",
		channel = "#general",
		content = [[ayesha  9:41 PM
  @wei closed all my tickets, pushed to prod, wrote documentation and  booked a flight without ever leaving emacs
wei  9:42 PM
  Great operating system, I wonder when it'll get a good text editor.
wei  9:42 PM
  How's that pinky doing?
wei  9:43 PM
  You should consider evil-mode on Doom emacs, get a feel for how a good editor works.
priya  9:47 PM
  Guys im scared for the launch, AI-generated code is a war crime. No way the launch goes well
priya  9:48 PM
  said that to arjun's face an hour ago and i stand by it
wei  9:50 PM
  brb, trent needs the AV rig in the den fixed before the demo
ayesha  9:58 PM
  @channel balatro bracket is running in the living room all night, get in here
daniel  10:01 PM
  can't, going for the office record, don't jinx it
ayesha  10:03 PM
  does anyone know why the wine cellar smart lock keeps triggering
wei  10:05 PM
  ok the emacs/vim debate ends NOW. living room. @everyone.
]],
	},

	-- ---------------- Home Office ----------------

	draft_email = {
		sprite  = "scroll",
		popup   = "laptop",
		content = [==[An unsent draft is open on the desktop:

  Subject: <no subject>
  To: Trent

  Hi,
  I've been going over the Q3 infra numbers and something is
  wrong. Compute utilization on the training cluster doesn't
  match the invoiced hours. I've traced about $310K to a vendor
  account that doesn't correspond to anything in our
  [The rest of the message is corrupted]]==],
	},

	repo_log = {
		sprite  = "laptop",
		popup   = "laptop",
		content = [[Recently-cloned repositories on this machine:

  jessai-agent-core
  hotfix-oct14                (praghavan)
  creatine-cycle-calculator   (praghavan, personal)
  infra-billing-dashboard     (dlin)]],
	},

	cipher_note = {
		sprite  = "scroll",
		hidden  = true,
		content = [[A sticky note stuck under the keyboard tray:

        IRAJORYH

  (shift three back, same as always)]],
	},

	slack_eng_help = {
		sprite  = "laptop",
		popup   = "slack",
		channel = "#eng-help",
		content = [[ayesha  9:36 PM
  stuck in vim on the prod box. how do i find and replace? @priya
priya  9:37 PM
  :s/old/new/ does the first match on a line, add g for all of them
  :%s/old/new/g for the whole file — same syntax as sed
ayesha  9:38 PM
  so basically sed -i 's/old/new/g' on the file. got it, hate it
priya  9:38 PM
  you'll live]],
	},

	slack_trent_dm = {
		sprite  = "laptop",
		popup   = "slack",
		channel = "DM: trent kessler",
		content = [[trent  10:33 PM
  grab the signed Meridian paperwork off the server-room box? need it
  for the board packet
trent  10:34 PM
  You can find the code word on the sticky note in the office under the desk.
  usual way:
  a=1 z=26, then mod 8 each letter. the code is three digits — the repeated
  letter, then the ^ letter, then the $ one. that last digit, keep it
  if it's odd, otherwise minus one.
trent  10:35 PM
  don't paste the actual number in here or I WILL fire you!]],
	},

	-- ---------------- The Den ----------------

	victim = {
		sprite  = "bottle",
		content = [[Arjun Mehta, 32. Found unresponsive around 10:20 PM.

A half-finished bottle of kombucha sits beside him. The
symptoms — the racing-then-failing heart, the dilated pupils —
are consistent with a cardiac-glycoside overdose. That compound
is derived from foxglove: medicinal in tiny doses, lethal in
excess.

Time of death: 10:05–10:20 PM.]],
	},

	party_statements = {
		sprite  = "scroll",
		popup   = "laptop",
		content = [[Statements taken in the first hour:

Ayesha Raza:
  "Wei and I were fighting over editors in the Living Room
   from about 10:05 until Trent's toast. Half the party was
   watching. Ask literally anyone."

Wei Zhao:
  "I fixed the AV rig in the Den earlier — like 9:50 — for the
   demo. After that I was arguing with Ayesha in front of
   everyone, then Priya and I grabbed espresso."

Priya Raghavan:
  "I was pushing a hotfix most of the night from the garage.
   Yes, I yelled at Arjun earlier. I did not touch him."

Daniel Lin:
  "I was in the home office playing Balatro. Didn't want
   to jinx it, so I kept to myself. Didn't even hear the
   emacs/vim thing kick off."
]],
	},

	calendar_note = {
		sprite  = "scroll",
		popup   = "laptop",
		content = [[A reminder is still lit on Arjun's phone on the side table:

  10:00 PM — Meet D. in the Den. Show him the billing
             numbers before I show Trent. Hoping there's
             an explanation.]],
	},

	-- ---------------- .closet (hidden, off the Den) ----------------

	draft_email_continued = {
		sprite  = "scroll",
		popup   = "laptop",
		content = [[The rest of corrupted email:

  ...doesn't correspond to anything in our approved vendor list.
  The account is provisioned under `dlin-admin`. I'll ask Daniel
  first, maybe he knows what this is.

  I've asked him to meet me at 10 in the Den.]],
	},

	-- ---------------- Sunroom ----------------

	espresso_bar = {
		sprite  = "cups",
		content = [[The espresso bar in the sunroom.

Two used cups sit in the drip tray, still faintly warm. Someone
made coffee for two here this evening.]],
	},

	keycard = {
		sprite  = "keycard",
		content = [[A spare guest badge, left on the counter.

It's the kind handed out at the door tonight — and it still
scans. The house's smart locks read these. You could carry it
to a door that won't open.]],
	},

	-- ---------------- Wine Cellar (mv-key gated) ----------------

	badge = {
		sprite  = "badge",
		content = [[A company badge lies face-down between two wine racks:

        DANIEL LIN
        Infrastructure

]],
	},

	cellar_access_log = {
		sprite  = "laptop",
		popup   = "laptop",
		content = [[Wine-cellar smart-lock scan log:

  9:44 PM   badge scan: staff (catering, exiting)
  10:12 PM  badge scan: dlin
  --        no other scans 9:45 PM - 10:30 PM

Whoever came down here at 10:12 PM came in on Daniel Lin's badge.]],
	},

	-- ---------------- Garage ----------------

	deploy_log = {
		sprite  = "laptop",
		popup   = "laptop",
		content = [[Pull request #482 — hotfix-oct14 -> main
  author: praghavan

  10:02 PM  checks started
  10:07 PM  tests running
  10:19 PM  all checks passed  [ok]
  10:21 PM  merged into main by praghavan]],
	},

	-- ---------------- Game Room ----------------

	office_meme = {
		sprite  = "scroll",
		hidden  = true,
		content = [[A printout pinned to the arcade cabinet — "hackathon 2024":

        GZYH ZIV YVGGVI

  (A<->Z, B<->Y, C<->X, ...).]],
	},

	slack_grep_help = {
		sprite  = "laptop",
		popup   = "slack",
		channel = "DM: wei zhao",
		content = [[leo  9:44 PM
  wei how do i find which file mentions something without opening every one
wei  9:45 PM
  grep -r <name>. searches every file, prints the hits with filenames
leo  9:46 PM
  and if i just want the filenames, not all the lines
wei  9:46 PM
  grep -rl <name>. a handle turns up in more places than you'd think
wei  9:47 PM
  also ^ anchors the start of a line, $ the end — ^foo matches lines
  starting with foo, foo$ ones ending with it]],
	},

	-- ---------------- Server Room (chmod-locked) ----------------

	billing_audit = {
		sprite  = "laptop",
		popup   = "laptop",
		content = [[Q3 Infrastructure Cost Review (finance draft):

  ~$310,000 in compute spend routed through a vendor account,
  "Meridian Compute Partners." No signed contract on file.
  Payment authorization and account provisioning both trace
  back to a single admin: Daniel Lin (dlin-admin).

This is the money Arjun found.]],
	},

	dosage_log = {
		sprite  = "laptop",
		popup   = "laptop",
		content = [[Personal spreadsheet, "HRV Stack — n=1":

  A week-by-week self-experiment log. Among the usual magnesium
  and creatine entries, one is dosed daily for a month:

        foxglove leaf extract

  Margin note: "therapeutic window is narrow — don't get
  creative with this one."

]],
	},

	slack_final = {
		sprite  = "laptop",
		popup   = "slack",
		channel = "DM: daniel lin",
		content = [[daniel  10:41 PM
  in the office playing balatro, didn't even hear the emacs/vim thing kick off lol]],
	},

	slack_draft = {
		sprite  = "laptop",
		popup   = "slack",
		channel = "DM: daniel lin (draft)",
		hidden  = true,
		content = [[daniel  (draft — never sent)
  in the office playing balatro. Did go out for 5-10 mins to grab something, didn't even hear the emacs/vim thing kick off lol]],
	},

	audit_stream = {
		sprite   = "laptop",
		popup    = "laptop",
		filename = "audit_stream.log",
		content  = [[# facility access stream — raw
# infra service account 'svc-agent' provisioned by dlin, Oct 14

10:01:22  svc-agent  auth  home_office
10:04:07  svc-agent  scan  den
10:09:55  svc-agent  auth  server_room
10:12:31  svc-agent  scan  cellar
10:15:48  svc-agent  auth  home_office]],
	},

}

return M
