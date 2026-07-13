-- screens/boot.lua
-- Startup boot animation. A fake terminal that "types out" a scripted sequence
-- of bash commands to launch the game (Matrix-ish green-on-black), then hands
-- off to the "play" title screen. Plays once at app launch.

Screen = require("screen")
Render = require("render")

local M = {}

-- Scripted lines the fake shell types out, in order. A mix of prompt lines
-- (bash commands the "player" appears to type) and canned output lines the
-- machine prints back. Filled in during implementation; thematically these
-- boot the mystery (clone repo, decrypt evidence, launch the terminal, etc.).
local SCRIPT = {}

-- Animation state (reset in M.enter):
--   line_index   -- which SCRIPT entry is currently being typed
--   char_index   -- how many chars of that entry are revealed
--   typed        -- list of fully-revealed lines to draw above the active one
--   char_timer   -- accumulates dt to pace one character per keystroke interval
--   cursor_*     -- blink state for the block cursor at the type head
--   done         -- true once the whole SCRIPT is typed (triggers handoff)
local anim = {}

function M.enter()
  -- Reset `anim` to the start: first line, zero chars revealed, empty `typed`,
  -- fresh timers/cursor, done = false.
end

function M.update(dt)
  -- Advance the typewriter: accumulate dt and reveal one more character of the
  -- current line each keystroke interval, inserting short pauses between lines.
  -- When the last SCRIPT line finishes, transition to "play" (after a brief
  -- hold). Also drive the cursor blink.
  --
  -- STUB: no animation yet — fall straight through to the title screen so the
  -- game still launches while this is unimplemented.
  Screen.set("play")
end

function M.draw()
  -- Black screen; draw `typed` lines + the partially-typed active line in the
  -- terminal font tinted Matrix-green, with a blinking block cursor at the head.
end

function M.keypressed(key)
  -- Any key skips the boot animation and jumps straight to the title screen.
  Screen.set("play")
end

return M
