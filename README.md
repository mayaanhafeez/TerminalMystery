# Terminal Mystery

A small murder-mystery game played through a fake terminal. The mansion is
laid out as a virtual filesystem — rooms are directories, evidence is files
— and you solve the case by walking around, reading clues, and using
`grep` to draw lines between them.

It is the autumn of 1923. Lord Edmund Ashworth lies dead in his Study at
Ashworth Manor. The constabulary is two hours away; you are the nearest
investigator, and the killer is still in the house. Four guests, six rooms,
one murder — solvable in a sitting.

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
Save** if you have a saved investigation). The left panel is your terminal;
the right panel is a live map of the house. Type commands into the prompt.

Some commands are available immediately; two unlock as you investigate:

- `cat <file>` unlocks once you've stepped outside the Foyer at least once.
- `grep` unlocks once you've read two pieces of evidence.

Type `help` at any time for the current command list. The full command set:

| command | what it does |
| ------- | ------------ |
| `ls [-a]` | list the current room (`-a` shows hidden files) |
| `cd <room>` | move to an adjacent room (`cd` alone returns to the Foyer) |
| `cd ..` / `cd ~` | go up to the Foyer; `cd ../<room>` goes up then in |
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
| `echo <text>` | repeat text back |
| `accuse <name>` | name the murderer (surname or full name) |
| `help` | show the available commands |
| `exit` | leave to the menu (`exit save` to keep progress, `exit nosave` to abandon) |

`grep` matching is **plain text and case-insensitive**, so `grep digitalis`
and `grep DIGITALIS` behave the same. Quote multi-word patterns:
`grep "R.C." torn_letter.txt`. Filenames (as shown by `ls`) are
case-sensitive, Unix-style.

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
macOS).

---

## Project layout

```
terminal_mystery/
├── main.lua          LÖVE callbacks; wires screens + render together
├── conf.lua          window / runtime config (1280×800, resizable)
├── screen.lua        tiny screen-stack manager (register / set / dispatch)
├── screens/
│   ├── play.lua      title screen (Play / Exit)
│   ├── play_menu.lua New Game / Continue From Save / Back
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
├── render.lua        all drawing: terminal pane, map, status bar, overlays
├── save.lua          serialize / restore game state to the save directory
├── test/             headless Lua test suite (world, navigation, items, completion)
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

### A monospace font

The game ships with `handwriting.ttf` and loads it automatically. To use a
different face, drop your own `.ttf` in and point the loader at it —
[Fira Code](https://github.com/tonsky/FiraCode) or
[JetBrains Mono](https://www.jetbrains.com/lp/mono/) both work well.

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

- The first thing to do is `ls`, then read `welcome.txt` once `cat` unlocks
  (step into another room first).
- The torn letter in the Library names a suspect by their initials.
- `grep -r` is the speedrun tool. One well-chosen pattern can collapse the
  suspect list in a single command.
