-- vim.lua — a bare-bones modal editor for taking notes mid-game.
--
-- Owns everything except drawing: the buffer, the cursor, the mode machine, the
-- `:` command line, and the notes file on disk. render.lua draws it
-- (draw_vim_view), screens/game.lua feeds it input and freezes the terminal
-- while it is open, commands/meta.lua opens it.
--
-- `vim` here is a plain state table (see M.open); every function takes it as
-- its first argument, the same way commands/ take `state`. No love.graphics
-- calls live here.
--
-- Bytes, not UTF-8: the buffer is indexed with plain string.sub, so a pasted
-- multibyte glyph would be split by the cursor.

local Audio = require("audio")

local M = {}

-- The single scratch pad. `vim`, `nvim` and `vi` all open this one file no
-- matter what is typed after them, so there is no filename argument anywhere.
local NOTES_DIR = "notes"
local NOTES_NAME = "notes.txt"
local NOTES_PATH = NOTES_DIR .. "/" .. NOTES_NAME

M.NAME = NOTES_NAME -- shown in the editor's status line by render.lua

-- ---------- persistence ----------
-- The scratch pad is tied to the run, not to the process. It lives in
-- state.notes for the session (so a new game starts empty), and only reaches
-- disk when the game itself is saved — which is why `:w` commits to
-- state.notes rather than writing the file: `exit nosave` must discard the
-- session's notes along with everything else it discards.
--
--   new game      World.new_state() -> notes = { "" }
--   :w            buffer -> state.notes            (session only)
--   exit save     state.notes -> notes.txt         (save.lua)
--   exit nosave   nothing written; notes.txt keeps the last saved run's text
--   continue      notes.txt -> state.notes         (screens/game.lua)
--
-- notes.txt itself is plain newline-joined text in LÖVE's save dir, readable
-- as-is outside the game.

-- Read NOTES_PATH into a list of lines. Missing/empty file -> { "" }.
local function read_notes()
	if not love.filesystem.getInfo(NOTES_PATH) then
		return { "" }
	end
	local text = love.filesystem.read(NOTES_PATH)
	if not text or text == "" then
		return { "" }
	end
	-- Drop the single trailing newline the writer adds; otherwise it would read
	-- back as an extra empty line every time the file is opened.
	text = text:gsub("\r\n", "\n"):gsub("\n$", "")
	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end
	if #lines == 0 then
		return { "" }
	end
	return lines
end

local function copy_lines(lines)
	local out = {}
	for i, line in ipairs(lines) do
		out[i] = line
	end
	if #out == 0 then
		out[1] = ""
	end
	return out
end

-- Called by save.lua when the run is saved: state.notes -> notes.txt.
function M.save_notes(state)
	love.filesystem.createDirectory(NOTES_DIR)
	local lines = state.notes or { "" }
	local ok, err = love.filesystem.write(NOTES_PATH, table.concat(lines, "\n") .. "\n")
	if not ok then
		print(err)
	end
end

-- Called by screens/game.lua when a saved run is continued: notes.txt -> lines.
function M.load_notes()
	return read_notes()
end

-- ---------- buffer helpers ----------

-- Clamp vim.line / vim.col back into the buffer after any edit or motion. The
-- cursor may sit one past the last character (where `a` and insert mode put
-- it), which real vim only allows in insert mode — close enough here.
local function clamp(vim)
	if vim.line < 1 then
		vim.line = 1
	elseif vim.line > #vim.lines then
		vim.line = #vim.lines
	end
	local len = #vim.lines[vim.line]
	if vim.col < 0 then
		vim.col = 0
	elseif vim.col > len then
		vim.col = len
	end
end

local function insert_char(vim, c)
	local line = vim.lines[vim.line]
	vim.lines[vim.line] = line:sub(1, vim.col) .. c .. line:sub(vim.col + 1)
	vim.col = vim.col + #c
	vim.dirty = true
end

local function backspace(vim)
	local line = vim.lines[vim.line]
	if vim.col > 0 then
		vim.lines[vim.line] = line:sub(1, vim.col - 1) .. line:sub(vim.col + 1)
		vim.col = vim.col - 1
	elseif vim.line > 1 then
		-- At column 0: join this line onto the end of the previous one.
		local prev = vim.lines[vim.line - 1]
		vim.col = #prev
		vim.lines[vim.line - 1] = prev .. line
		table.remove(vim.lines, vim.line)
		vim.line = vim.line - 1
	else
		return -- start of the buffer, nothing to delete
	end
	vim.dirty = true
end

-- Split the current line at the cursor.
local function newline(vim)
	local line = vim.lines[vim.line]
	vim.lines[vim.line] = line:sub(1, vim.col)
	table.insert(vim.lines, vim.line + 1, line:sub(vim.col + 1))
	vim.line = vim.line + 1
	vim.col = 0
	vim.dirty = true
end

-- ---------- : command line ----------

-- Commit the buffer to the session (state.notes). It only reaches notes.txt if
-- the run is later saved — see the persistence note at the top.
local function save(vim)
	vim.state.notes = copy_lines(vim.lines)
	vim.dirty = false
	vim.msg = string.format('"%s" %dL written', NOTES_NAME, #vim.lines)
	Audio.play("write_ok")
end

-- Tear the editor down. Same shape as meta.lua's `exit`: call straight back
-- into the game screen, which owns the layout toggle.
local function quit()
	GameScreen.close_vim()
end

-- Run whatever was typed after `:`. Unknown commands and `q` with unsaved
-- changes set vim.msg (E492 / E37) and stay open.
local function run_command(vim)
	local cmd = vim.cmd:gsub("^%s+", ""):gsub("%s+$", "")
	if cmd == "w" then
		save(vim)
	elseif cmd == "wq" or cmd == "x" then
		save(vim)
		quit()
	elseif cmd == "q" then
		if vim.dirty then
			vim.msg = "E37: No write since last change (add ! to override)"
			Audio.play("bell")
		else
			quit()
		end
	elseif cmd == "q!" then
		quit()
	else
		vim.msg = "E492: Not an editor command: " .. cmd
		Audio.play("bell")
	end
end

-- ---------- normal mode ----------

-- Dispatch one printable normal-mode key: h/j/k/l motion, i/a/o into insert, x
-- delete, `:` into the command line. Driven from text_input rather than
-- keypressed so that entering insert mode doesn't also type the key that did it.
local function normal_key(vim, c)
	if c == "h" then
		vim.col = vim.col - 1
	elseif c == "l" then
		vim.col = vim.col + 1
	elseif c == "j" then
		vim.line = vim.line + 1
	elseif c == "k" then
		vim.line = vim.line - 1
	elseif c == "0" then
		vim.col = 0
	elseif c == "$" then
		vim.col = #vim.lines[vim.line]
	elseif c == "i" then
		vim.mode = "insert"
	elseif c == "a" then
		vim.mode = "insert"
		vim.col = vim.col + 1
	elseif c == "o" then
		table.insert(vim.lines, vim.line + 1, "")
		vim.line = vim.line + 1
		vim.col = 0
		vim.mode = "insert"
		vim.dirty = true
	elseif c == "s" then
		-- substitute: drop the character under the cursor, then insert
		local line = vim.lines[vim.line]
		if vim.col < #line then
			vim.lines[vim.line] = line:sub(1, vim.col) .. line:sub(vim.col + 2)
			vim.dirty = true
		end
		vim.mode = "insert"
	elseif c == "x" then
		local line = vim.lines[vim.line]
		if vim.col < #line then
			vim.lines[vim.line] = line:sub(1, vim.col) .. line:sub(vim.col + 2)
			vim.dirty = true
		end
	elseif c == ":" then
		vim.mode = "command"
		vim.cmd = ""
		vim.msg = ""
	end
	clamp(vim)
end

-- ---------- public ----------

-- Open the scratch pad over the run's notes and return a fresh vim state. The
-- buffer is a copy: `:q!` discards it, `:w` copies it back into state.notes.
function M.open(state)
	return {
		state = state, -- the run the scratch pad belongs to
		lines = copy_lines(state.notes or { "" }),
		line = 1, -- cursor line, 1-based
		col = 0, -- chars before the cursor on that line
		mode = "normal", -- "normal" | "insert" | "command"
		cmd = "", -- text typed after `:` while mode == "command"
		msg = "", -- status line: errors, ":w" confirmations
		scroll = 0, -- first visible display row; maintained by the renderer
		dirty = false, -- unsaved changes since the last :w
	}
end

-- Printable text. Meaning depends on mode: a command in normal, a character in
-- insert, command-line text after `:`.
function M.text_input(vim, t)
	if vim.mode == "command" then
		vim.cmd = vim.cmd .. t
	elseif vim.mode == "insert" then
		insert_char(vim, t)
	else
		normal_key(vim, t)
	end
end

-- Non-printable keys: escape, return, backspace, arrows.
function M.keypressed(vim, key)
	if vim.mode == "command" then
		if key == "return" or key == "kpenter" then
			vim.mode = "normal"
			run_command(vim) -- reads vim.cmd, so clear it only afterwards
			vim.cmd = ""
		elseif key == "backspace" then
			if vim.cmd == "" then
				vim.mode = "normal" -- backspacing past the `:` leaves the prompt
			else
				vim.cmd = vim.cmd:sub(1, -2)
			end
		elseif key == "escape" then
			vim.mode = "normal"
			vim.cmd = ""
		end
		return
	end

	if key == "escape" then
		if vim.mode == "insert" then
			vim.mode = "normal"
			vim.col = vim.col - 1 -- vim steps back off the character just typed
			clamp(vim)
		end
		return
	end

	if vim.mode == "insert" then
		if key == "return" or key == "kpenter" then
			newline(vim)
			return
		elseif key == "backspace" then
			backspace(vim)
			return
		end
	end

	-- Arrows move in both modes.
	if key == "left" then
		vim.col = vim.col - 1
	elseif key == "right" then
		vim.col = vim.col + 1
	elseif key == "up" then
		vim.line = vim.line - 1
	elseif key == "down" then
		vim.line = vim.line + 1
	else
		return
	end
	clamp(vim)
end

return M
