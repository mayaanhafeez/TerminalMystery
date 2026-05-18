# Terminal Mystery

A small murder-mystery game played through a fake terminal. The mansion is
laid out as a virtual filesystem — rooms are directories, evidence is files
— and you solve the case by walking around, reading clues, and using
`grep` to draw lines between them.

This is a **vertical slice**, not a full game: one murder, four suspects,
five rooms. Solvable in one sitting.

Built in pure Lua for [LÖVE](https://love2d.org/) 11.x. No external
dependencies.

---

## Install LÖVE

You need LÖVE 11.x. (Tested against 11.4 and 11.5.)

### macOS
```bash
brew install --cask love
```
or download the `.dmg` from https://love2d.org/.

### Linux
```bash
# Debian / Ubuntu
sudo apt install love
# Arch
sudo pacman -S love
```

### Windows
Download the installer from https://love2d.org/ and let it associate
`.love` files.

## Run the game

From this directory:

```bash
love .
```

On macOS, if the `love` CLI isn't on your `$PATH`, you can also do:

```bash
/Applications/love.app/Contents/MacOS/love .
```

---

## How to play

You start in the Foyer of Ashworth Manor. The left panel is your terminal;
the right panel is a map of the house. Type commands into the prompt.

The commands available to you grow as you investigate. You start with:

| command            | what it does                                     |
| ------------------ | ------------------------------------------------ |
| `ls`               | list the contents of the current room            |
| `cd <room>`        | move to an adjacent room (`cd` alone shows exits)|
| `cd ..`            | go back to the room you came from                |
| `echo <text>`      | repeat text                                      |
| `help`             | show currently-available commands                |
| `accuse <name>`    | name the murderer (surname or full name is fine) |

Two more commands unlock as you go:

- `cat <file>` — read a piece of evidence. Unlocks once you've stepped
  outside the Foyer at least once.
- `grep <pattern> <file>` / `grep -r <pattern>` — search inside one file,
  or recursively across every file in every room you have visited. Unlocks
  once you've read two pieces of evidence.

Pattern matching is **plain text and case-insensitive**, so `grep digitalis`
and `grep DIGITALIS` behave the same. Quote multi-word patterns:
`grep "R.C." torn_letter.txt`.

### Controls

- **Enter** — run command
- **Up / Down** — walk through command history
- **Page Up / Page Down** — scroll the terminal
- **Esc** — quit
- **R** — replay (on the win screen only)

### Goal

Find the killer. When you're sure, type `accuse <name>`. A wrong
accusation gives you a hint and lets you keep playing; a correct one
ends the case and shows your time and command count.

Your personal best (fastest time and fewest commands) is saved locally
between runs, in LÖVE's per-app save directory (printed by
`love.filesystem.getSaveDirectory()` — usually `~/Library/Application
Support/LOVE/terminal_mystery/` on macOS).

---

## Project layout

```
terminal_mystery/
├── main.lua        love callbacks, input, save/load
├── conf.lua        love window/runtime config
├── world.lua       rooms, files, suspects, mutable game state
├── commands.lua    parser + per-command handlers (pure-ish)
├── render.lua      drawing: terminal, map, status bar, win overlay
└── README.md
```

The game logic in `world.lua` and `commands.lua` doesn't touch
`love.graphics` at all, so the core is independently testable.

### Optional: a real monospace font

LÖVE doesn't ship a monospace face. Drop any `.ttf` you like into this
directory as `font.ttf` and the game will pick it up automatically.
[Fira Code](https://github.com/tonsky/FiraCode) or
[JetBrains Mono](https://www.jetbrains.com/lp/mono/) both work nicely.

---

## Spoiler-free hints

- The very first thing to do is `ls`, then read `welcome.txt` once `cat`
  unlocks (you'll need to step into another room first).
- The torn letter in the Library names a suspect by their initials.
- `grep -r` is the speedrun tool. One well-chosen pattern can collapse
  the suspect list in a single command.
