-- test/test_vim.lua — the notes editor (vim.lua): modes, editing, : commands,
-- and the session/save persistence rules.
--
-- vim.lua touches love.filesystem (notes.txt) and calls back into the
-- GameScreen global on :q, the same way commands/meta.lua's `exit` does. Both
-- are stubbed here. love.filesystem is *mutated* rather than replaced so the
-- love.timer shim other suites install survives, and this file is required
-- last in test/run.lua so the GameScreen global can't leak into them.

local T = require("test.runner")

local store = {}
love = love or {}
love.filesystem = {
    write = function(path, content) store[path] = content; return true end,
    read = function(path) return store[path] end,
    getInfo = function(path) return store[path] and {} or nil end,
    remove = function(path) store[path] = nil; return true end,
    createDirectory = function() return true end,
}

local Vim = require("vim")
local World = require("world")
local Save = require("save")

local NOTES = "notes/notes.txt"

local closed = false
GameScreen = { close_vim = function() closed = true end }

-- Feed a string through text_input one character at a time, as LÖVE would.
local function type_str(v, s)
    for c in s:gmatch(".") do
        Vim.text_input(v, c)
    end
end

local function open_pad(lines)
    closed = false
    return Vim.open({ notes = lines or { "" } })
end

-- -----------------------------------------------------------------------
T.suite("vim — modes and editing")

T.test("a new run starts with an empty scratch pad", function()
    local state = World.new_state()
    T.eq(#state.notes, 1)
    T.eq(state.notes[1], "")
end)

T.test("i enters insert mode, Esc returns to normal", function()
    local v = open_pad()
    type_str(v, "i")
    T.eq(v.mode, "insert")
    type_str(v, "dlin badge 10:12")
    Vim.keypressed(v, "escape")
    T.eq(v.mode, "normal")
    T.eq(v.lines[1], "dlin badge 10:12")
    T.ok(v.dirty, "typing should mark the buffer dirty")
end)

T.test("Enter splits the line at the cursor", function()
    local v = open_pad()
    type_str(v, "iab")
    Vim.keypressed(v, "return")
    type_str(v, "cd")
    T.eq(#v.lines, 2)
    T.eq(v.lines[1], "ab")
    T.eq(v.lines[2], "cd")
end)

T.test("backspace at column 0 joins onto the previous line", function()
    local v = open_pad({ "foxglove", "is his word" })
    v.line, v.col = 2, 0
    type_str(v, "i")
    Vim.keypressed(v, "backspace")
    T.eq(#v.lines, 1)
    T.eq(v.lines[1], "foxgloveis his word")
end)

T.test("hjkl move the cursor and clamp to the buffer", function()
    local v = open_pad({ "abc", "de" })
    type_str(v, "lll") -- past the end of "abc" -> clamped
    T.eq(v.col, 3)
    type_str(v, "j") -- line 2 is shorter, so the column clamps with it
    T.eq(v.line, 2)
    T.eq(v.col, 2)
    type_str(v, "kkk") -- above the first line -> clamped
    T.eq(v.line, 1)
    type_str(v, "0")
    T.eq(v.col, 0)
    type_str(v, "$")
    T.eq(v.col, 3)
end)

T.test("x deletes under the cursor, o opens a line, s substitutes", function()
    local v = open_pad({ "abc" })
    type_str(v, "x")
    T.eq(v.lines[1], "bc")
    type_str(v, "onew")
    Vim.keypressed(v, "escape")
    T.eq(#v.lines, 2)
    T.eq(v.lines[2], "new")
    v.col = 0
    type_str(v, "sN")
    T.eq(v.lines[2], "New")
    T.eq(v.mode, "insert")
end)

-- -----------------------------------------------------------------------
T.suite("vim — : commands")

T.test(":w commits the buffer to the session, not to disk", function()
    store[NOTES] = nil
    local state = { notes = { "" } }
    local v = Vim.open(state)
    type_str(v, "ifoxglove")
    Vim.keypressed(v, "escape")
    type_str(v, ":w")
    Vim.keypressed(v, "return")
    T.ok(not v.dirty, ":w should clear the dirty flag")
    T.eq(state.notes[1], "foxglove")
    T.eq(store[NOTES], nil, ":w must not write notes.txt on its own")
end)

T.test(":q refuses while there are unwritten changes", function()
    local v = open_pad()
    type_str(v, "ihmm")
    Vim.keypressed(v, "escape")
    type_str(v, ":q")
    Vim.keypressed(v, "return")
    T.ok(not closed, ":q must not quit with unsaved changes")
    T.ok(v.msg:find("E37", 1, true), "expected E37, got: " .. v.msg)
end)

T.test(":q! discards the buffer and closes", function()
    local state = { notes = { "kept" } }
    closed = false
    local v = Vim.open(state)
    type_str(v, "ithrown away")
    Vim.keypressed(v, "escape")
    type_str(v, ":q!")
    Vim.keypressed(v, "return")
    T.ok(closed, ":q! should close the editor")
    T.eq(state.notes[1], "kept", "unwritten edits must not reach the session")
end)

T.test(":wq commits and closes", function()
    local state = { notes = { "" } }
    closed = false
    local v = Vim.open(state)
    type_str(v, "inote")
    Vim.keypressed(v, "escape")
    type_str(v, ":wq")
    Vim.keypressed(v, "return")
    T.ok(closed)
    T.eq(state.notes[1], "note")
end)

T.test("an unknown : command reports E492 and stays open", function()
    local v = open_pad()
    type_str(v, ":wat")
    Vim.keypressed(v, "return")
    T.ok(not closed)
    T.ok(v.msg:find("E492", 1, true), "expected E492, got: " .. v.msg)
end)

T.test("Esc and backspace back out of the : prompt", function()
    local v = open_pad()
    type_str(v, ":w")
    Vim.keypressed(v, "escape")
    T.eq(v.mode, "normal")
    type_str(v, ":")
    Vim.keypressed(v, "backspace") -- backspacing past the ':' leaves the prompt
    T.eq(v.mode, "normal")
end)

-- -----------------------------------------------------------------------
T.suite("vim — session persistence")

T.test("notes.txt round-trips as plain text", function()
    store[NOTES] = nil
    Vim.save_notes({ notes = { "dlin 10:12", "foxglove" } })
    T.eq(store[NOTES], "dlin 10:12\nfoxglove\n")
    local loaded = Vim.load_notes()
    T.eq(#loaded, 2)
    T.eq(loaded[2], "foxglove")
end)

T.test("a missing notes.txt loads as one empty line", function()
    store[NOTES] = nil
    local loaded = Vim.load_notes()
    T.eq(#loaded, 1)
    T.eq(loaded[1], "")
end)

T.test("the buffer is a copy, so edits don't leak until :w", function()
    local state = { notes = { "original" } }
    local v = Vim.open(state)
    v.lines[1] = "scribbled"
    T.eq(state.notes[1], "original")
end)

T.test("saving the run writes the notes alongside save_data.txt", function()
    store[NOTES] = nil
    local state = World.new_state()
    state.notes = { "written with the save" }
    Save.save_state(state, "test_vim_save.txt")
    T.ok(store["test_vim_save.txt"], "expected the save file")
    T.eq(store[NOTES], "written with the save\n")
    store["test_vim_save.txt"] = nil
end)
