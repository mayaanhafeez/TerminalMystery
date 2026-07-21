# Terminal Mystery

A small murder-mystery game played through a fake terminal. The mansion is
laid out as a virtual filesystem — rooms are directories, evidence is files
— and you solve the case by walking around, reading clues, and using
`grep` to draw lines between them.

Strictly.ai just closed its Series C. At the launch party in the CEO's
house, Arjun Mehta — VP of AI Research — is found dead in the Den, an empty
bottle of kombucha beside him. Legal wants it quiet until you've had a look.
Four engineers were in range during the window, and one of them is still
here. Eight rooms, one murder — solvable in a sitting.

Built in pure Lua for [LÖVE](https://love2d.org/) 11.x, with a browser
build via [love.js](https://github.com/Davidobot/love.js). No external Lua
dependencies.

---

## Play in the browser

The game is deployed to Vercel as a WebAssembly build — no install needed.
See "Web build & deploy" below to build it yourself.

## Run natively

You need LÖVE 11.x (tested against 11.4 and 11.5).

### Install LÖVE

```bash
# macOS
brew install --cask love
# Debian / Ubuntu
sudo apt install love
# Arch
sudo pacman -S love
```
Windows: grab the installer from https://love2d.org/.

### Run the game

From this directory:

```bash
love .
```

On macOS, if the `love` CLI isn't on your `$PATH`:

```bash
/Applications/love.app/Contents/MacOS/love .
```

---

## How to play

You start at the title screen: **Play** → **New Game** (or **Continue From
Save** if you have a saved investigation), then pick a display mode —
**Full view** (terminal on the left, a live view of the room on the right)
or **Terminal only** (just the shell, full width). Type commands into the
prompt.

Nearly everything is available immediately. `grep` is the exception: it
unlocks once you've read two pieces of evidence.

Type `help` at any time for the current command list. The full command set:

| command | what it does |
| ------- | ------------ |
| `ls [-a]` | list the current room (`-a` shows hidden files) |
| `cd <room>` | move to an adjacent room (`cd` alone returns to the Entrance Hall) |
| `cd ..` / `cd ~` | go up to the Entrance Hall; `cd ../<room>` goes up then in |
| `cd -` | return to the previous room |
| `pwd` / `cwd` | print the current / previous room path |
| `cat <file>` | read a piece of evidence |
| `grep [flags] <pattern> <file>` | search inside files (`-r -v -n -l -a`; globs `*`, `.[^.]*`) |
| `find <name>` | locate a file across visited rooms |
| `diff <f1> <f2>` | compare two files (both must be `cat`'d first) |
| `mv <src> <room>` | move a file to a visited room |
| `cp <file> <room>` | copy a file to a visited room |
| `rm <file>` | destroy evidence — irreversible (`rm -f` skips the prompt) |
| `chmod <mode> <target>` | set permissions on a room or file |
| `sed 's/old/new/' <file>` | print the file with a substitution applied (`-i` edits in place, after `chmod +w`) |
| `vim` / `nvim` / `vi` | open the notes editor (`help vim` for the keys) |
| `echo <text>` | repeat text back |
| `accuse <name>` | name the murderer (surname or full name) |
| `help` | show the available commands |
| `exit` | leave to the menu (`exit save` to keep progress, `exit nosave` to abandon) |

`grep` matching is **plain text and case-insensitive**, so `grep kombucha`
and `grep KOMBUCHA` behave the same. Quote multi-word patterns:
`grep "home office" party_statements.txt`. Filenames (as shown by `ls`) are
case-sensitive, Unix-style.

### Taking notes

`vim` (or `nvim`, or `vi` — they all open the same scratch pad) opens a small
modal editor beside the terminal, replacing the map. The terminal is frozen
while it's open. Type `help vim` in game for the full list; the short version:

- `i` / `a` / `o` / `s` — insert before / after the cursor, on a new line
  below, or over the character under the cursor. **Esc** leaves insert mode.
- `h j k l` (or the arrows) to move, `0` / `$` for start / end of line,
  `x` to delete a character.
- `:w` write, `:q` quit (refused if you have unwritten changes), `:q!`
  quit and discard, `:wq` both. **Ctrl +/− /0** zooms the editor's text
  independently of the terminal's.

Notes are kept with the game: `exit save` stores them next to your save,
`exit nosave` throws away everything written that session, and a new game
starts with a blank pad.

### Controls

- **Enter** — run command
- **Tab** — autocomplete commands, rooms and filenames (press again to cycle)
- **Up / Down** — command history
- **Page Up / Page Down** — scroll the terminal; **Home / End** — jump
- **Ctrl/Cmd +/− /0** — zoom the font in / out / reset
- **Ctrl+W / Ctrl+U / Ctrl+Backspace** — delete word / line / word
- **Esc** — close an open evidence popup
- **R** — replay (on the win screen)

### Goal

Find the killer. When you're sure, type `accuse <name>`. A wrong accusation
lets you keep playing; a correct one ends the case and shows your time and
command count. Your personal best is tracked between runs, and `exit save`
lets you resume a partial investigation later. Saves live in LÖVE's per-app
save directory (`~/Library/Application Support/LOVE/terminal_mystery/` on
macOS) — alongside `notes/notes.txt`, which is the scratch pad as plain text
if you'd rather read it outside the game.

---

## Project layout

```
terminal_mystery/
├── main.lua          LÖVE callbacks; wires screens + render together
├── conf.lua          window / runtime config (1280×800, resizable)
├── screen.lua        tiny screen-stack manager (register / set / dispatch)
├── screens/
│   ├── boot.lua      fake boot sequence + ASCII banner, hands off to the title
│   ├── play.lua      title screen (Play / Exit)
│   ├── play_menu.lua New Game / Continue From Save / Back
│   ├── mode_select.lua  Full view / Terminal only picker
│   └── game.lua      the terminal UI: input, history, tab-complete, scroll
├── world.lua         rooms, suspects, evidence, mutable game state (no rendering)
├── items.lua         evidence/item definitions
├── commands/
│   ├── init.lua      tokenizer + dispatch (M.execute), command unlocks
│   ├── navigation.lua  ls, cd, pwd, cwd
│   ├── evidence.lua    cat, grep, find, diff
│   ├── items.lua       mv, cp, rm, chmod
│   ├── meta.lua        help, echo, exit, accuse
│   └── completion.lua  Tab-completion candidates
├── vim.lua           the in-game notes editor (buffer, modes, : commands)
├── render.lua        all drawing: terminal pane, map, editor pane, overlays
├── save.lua          serialize / restore game state to the save directory
├── headless/         run the game without LÖVE (engine, REPL, fuzzer, LLM player)
├── test/             headless Lua test suite (world, navigation, items, completion, vim)
├── server.js         static server with COOP/COEP headers for the web build
├── web-index.html    HTML template copied over love.js's default index
├── package.json      web build + Playwright test scripts
└── vercel.json       Vercel config (serves web/, sets cross-origin headers)
```

The game logic in `world.lua` and the `commands/` modules makes no
`love.graphics` calls, so the core is testable independently of the
framework.

### Tests

```bash
lua test/run.lua
```

A browser smoke test runs via Playwright:

```bash
npm test
```

### Fonts

Three faces ship in the repo root and load automatically (`render.lua`):

- `font_mono.ttf` — [JetBrains Mono](https://www.jetbrains.com/lp/mono/): the
  terminal, the notes editor, menus, and the "computer screen" popups (laptop
  logs, Slack), where columns need to line up.
- `monocraft.ttf` — the pixel face, used only in the room view: its name
  banner, item labels and minimap.
- `handwriting.ttf` — handwritten evidence in scroll popups.

Drop a `font.ttf` in the repo root to override the pixel face; it's
gitignored, so it stays local to your checkout.

---

## Web build & deploy

The browser version is LÖVE compiled to WebAssembly via love.js. You need
Node.js + npm.

```bash
npm install     # restore devDependencies (love.js, Playwright)
npm run build   # bundle .love → love.js → copy web-index.html into web/
npm run serve   # serve web/ at http://localhost:3000 with COOP/COEP headers
```

Deploy: push the repo — `vercel.json` serves `web/` and sets the
`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers that
the threaded WASM build requires. `web/` is a build artifact and is not
committed; build it in CI or before deploying.

> Note: `conf.lua` disables vsync because uncapped vsync starves the browser
> event loop and causes keyboard input lag. love.js's LuaJIT build also
> doesn't support `goto`/`::label::`, so the Lua source avoids them.

---

## Spoiler-free hints

- Start with `ls`, then `cat welcome.txt`. Read two files and `grep` opens up.
- Not everything is listed. `ls -a` shows the dotfiles, and there are several.
- `grep -r <word>` searches every room you've been in. One well-chosen word
  can collapse the suspect list in a single command.
- Two rooms don't open by walking into them: one wants something carried to
  it, the other wants a code you have to work out. Both tools are in `help`.
- Keep names, timestamps and chat handles straight in `vim` — this case turns
  on who was where, and when.
