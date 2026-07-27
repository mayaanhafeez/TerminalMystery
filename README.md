# Terminal Mystery

A murder-mystery game played through a fake terminal. The house is laid out as
a virtual filesystem — rooms are directories, evidence is files — and you solve
the case with `cd`, `cat` and `grep`.

Built in pure Lua for [LÖVE](https://love2d.org/) 11.x, with a browser build via
[love.js](https://github.com/Davidobot/love.js). No external Lua dependencies.

---

## The case

Strictly.ai has just closed its Series C. At the launch party in the CEO's
house, **Arjun Mehta** — VP of AI Research — is found dead in the Den, an empty
bottle of kombucha beside him. Legal wants it quiet until someone has had a
look, and that someone is you.

Four engineers were in range during the window and one of them is still in the
house. The evidence is scattered across eight rooms as badge logs, Slack
exports, billing audits and handwritten notes; some of it is hidden, some of it
is locked behind a door you have to work out how to open, and one document has
been quietly edited to remove a name. Read enough of it in the right order and
the killer is unambiguous.

Solvable in a sitting. Type `help` in game for the command list.

---

## Install

You need LÖVE 11.x (tested against 11.4 and 11.5).

```bash
# macOS
brew install --cask love
# Debian / Ubuntu
sudo apt install love
# Arch
sudo pacman -S love
```

Windows: grab the installer from https://love2d.org/.

## Run

From this directory:

```bash
love .
```

On macOS, if the `love` CLI isn't on your `$PATH`:

```bash
/Applications/love.app/Contents/MacOS/love .
```

It is not a demanding game — any machine from the last decade, OpenGL 2.1, and
about 200 MB of RAM. The window is 1280×800 by default and freely resizable
down to 800×500. Saves, notes and settings live in LÖVE's per-app save
directory (`~/Library/Application Support/LOVE/terminal_mystery/` on macOS).

## Web build

The browser version is LÖVE compiled to WebAssembly via love.js. Needs Node +
npm.

```bash
npm install     # restore devDependencies (love.js, Playwright)
npm run build   # bundle .love → love.js → copy web-index.html into web/
npm run serve   # serve web/ at http://localhost:3000 with COOP/COEP headers
```

Deploy by pushing the repo: `vercel.json` serves `web/` and sets the
`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers the
threaded WASM build requires. `web/` is a build artifact and is not committed.

---

## How it works

`main.lua` is the entry point. It registers the screens, then hands every
`love.*` callback straight through to `screen.lua`, a small registry that
dispatches `update` / `draw` / `keypressed` / `textinput` to whichever screen is
current. The game boots into `boot` (a fake POST sequence) → `play` (title) →
`play_menu` → `mode_select` → `game`.

`screens/game.lua` is the terminal itself: input buffer, command history,
Tab-completion, scrollback. Each line you enter goes to `commands.execute`,
which tokenizes it, checks the command is unlocked, and calls a handler in
`commands/` — one module per family (`navigation`, `evidence`, `items`, `meta`).
A handler is just `fn(state, args) -> string`; the string is printed.

That state comes from `world.lua`, which holds the rooms, suspects and mutable
run state, joined at startup against the evidence registry in `items.lua`.
Rooms are a flat table with a `parent` field — exits are derived, so adding a
room is one entry. Alongside it sit `vim.lua` (the in-game notes editor),
`audio.lua` (SFX and per-room ambience) and `save.lua` (state serialization).

The split that matters: `world.lua`, `items.lua`, `vim.lua` and `commands/`
make no `love.graphics` calls at all. All drawing lives in `render.lua` and the
screens. That keeps the entire game core testable without the framework, and it
is what lets `headless/` run the whole game — REPL, fuzzer, even an LLM
player — with no window open.

```
terminal_mystery/
├── main.lua       LÖVE callbacks; registers screens
├── conf.lua       window / runtime config
├── screen.lua     screen registry (register / set / dispatch)
├── screens/       boot, play, play_menu, mode_select, game
├── world.lua      rooms, suspects, evidence placement, run state
├── items.lua      evidence registry (sprites + contents)
├── commands/      tokenizer + dispatch, one module per command family
├── vim.lua        in-game notes editor
├── audio.lua      SFX and per-room ambience
├── render.lua     all drawing: terminal, room view, editor, overlays
├── save.lua       serialize / restore to the save directory
├── headless/      run the game without LÖVE (engine, REPL, fuzzer, LLM player)
├── test/          headless Lua test suite
└── web-index.html, server.js, vercel.json, package.json   web build + deploy
```

## Tests

```bash
lua test/run.lua   # headless Lua suite: world, commands, vim, save, solve
npm test           # Playwright smoke test against the web build
```
