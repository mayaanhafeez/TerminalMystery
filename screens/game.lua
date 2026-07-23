local World = require("world")
local utf8 = require("utf8")
local Commands = require("commands")
local Render = require("render")
local Completion = require("commands.completion")
local Screen = require("screen")
local Vim = require("vim")
local Audio = require("audio")

local state
local term
local best
local cursor_timer = 0

-- Live notes-editor state (vim.lua) while it's open, nil otherwise. Non-nil
-- means the terminal is frozen: every key goes to the editor instead.
local vim = nil
-- One-shot guard for the editor's ctrl +/-/0 zoom: those keys also fire a
-- textinput that insert mode would otherwise type into the buffer.
local vim_swallow_text = false

-- CRT switch animation. `mode` is "on" (power-on when the game screen is
-- entered) or "off" (power-off when exiting back to the title). `t` counts up to
-- `duration`; the shader progress runs 0->1 for "on" and 1->0 for "off". While
-- active, input is ignored; when an "off" run finishes it hands off to "play".
local crt = { active = false, mode = "on", t = 0, duration = 0.8 }
-- One-shot guard: a keypress that skips the CRT/intro also fires a paired
-- textinput for printable keys; this swallows that char so it isn't typed.
local crt_swallow_text = false

-- Interactive exit prompt. When active the terminal shows "Do you wish to
-- save? (Y/n)" and the next Y/N/Esc keypress resolves it (no Enter needed).
-- Input is otherwise frozen, mirroring popup_item / crt.
local exit_prompt = { active = false }

-- New-game intro typewriter: reveals the opening narration char-by-char over
-- ~12s. Skippable by any key / mouse press. Inactive for restored games.
local intro = { active = false }

local function load_best()
	if not love.filesystem.getInfo("scores.lua") then
		return nil
	end
	local content = love.filesystem.read("scores.lua")
	if not content then
		return nil
	end
	local chunk, err = load(content, "scores", "t", {})
	if not chunk then
		return nil
	end
	local ok, value = pcall(chunk)
	if
		ok
		and type(value) == "table"
		and type(value.best_time) == "number"
		and type(value.best_commands) == "number"
	then
		return value
	end
	return nil
end

local function save_best(b)
	local data = string.format("return { best_time = %.6f, best_commands = %d }", b.best_time, b.best_commands)
	love.filesystem.write("scores.lua", data)
end

local function push_text(text, kind)
	kind = kind or "output"
	table.insert(term.messages, { text = text, kind = kind })
	local wrapped = Render.wrap_text(text)
	for _, line in ipairs(wrapped) do
		table.insert(term.lines, { text = line, kind = kind })
	end
end

local function clear_tab_state()
	if not term or not term.tab_candidates then
		return
	end
	for i = #term.lines, 1, -1 do
		if term.lines[i].kind == "completion" then
			table.remove(term.lines, i)
		else
			break
		end
	end
	for i = #term.messages, 1, -1 do
		if term.messages[i].kind == "completion" then
			table.remove(term.messages, i)
		else
			break
		end
	end
	term.tab_candidates = nil
	term.tab_index = nil
end

local function rewrap_terminal()
	if not term then
		return
	end
	term.lines = {}
	for _, msg in ipairs(term.messages) do
		local wrapped = Render.wrap_text(msg.text)
		for _, line in ipairs(wrapped) do
			table.insert(term.lines, { text = line, kind = msg.kind })
		end
	end
end

-- First `n` UTF-8 characters of `s` (byte-safe, so multibyte glyphs like the em
-- dash are never split mid-sequence while typing).
local function utf8_prefix(s, n)
	if n <= 0 then
		return ""
	end
	local byte = utf8.offset(s, n + 1)
	return byte and s:sub(1, byte - 1) or s
end

-- Rebuild the terminal to show the intro typed so far: completed segments in
-- full plus the partially-typed current segment.
local function render_intro()
	term.messages = {}
	term.lines = {}
	for i = 1, math.min(intro.seg - 1, #intro.segments) do
		push_text(intro.segments[i].text, intro.segments[i].kind)
	end
	if intro.seg <= #intro.segments then
		local s = intro.segments[intro.seg]
		push_text(utf8_prefix(s.text, intro.char), s.kind)
	end
end

local INTRO_TYPING_SECONDS = 18 -- time spent actually typing (excludes pauses)
local INTRO_PARA_PAUSE = 1.0 -- extra hold after each paragraph

-- Split prose into paragraphs on blank lines (soft single newlines are kept and
-- reflowed by wrap_text, matching how the terminal normally renders it).
local function split_paragraphs(text)
	local paras = {}
	for p in (text .. "\n\n"):gmatch("(.-)\n\n") do
		if p ~= "" then
			paras[#paras + 1] = p
		end
	end
	return paras
end

-- Begin the typewriter reveal of the opening narration (new game only). Each
-- paragraph types out, then a blank line appears and the reveal pauses.
local function start_intro()
	local segments = {}
	local function add_block(text, kind)
		for _, p in ipairs(split_paragraphs(text)) do
			segments[#segments + 1] = { text = p, kind = kind }
			-- Blank spacer after the paragraph; the pause lands on it, so the
			-- gap shows first and then the reveal holds.
			segments[#segments + 1] = { text = "", kind = kind, pause_after = INTRO_PARA_PAUSE }
		end
	end
	add_block(World.intro, "system")
	add_block(World.rooms.foyer.description, "output")

	local total = 0
	for _, s in ipairs(segments) do
		s.len = utf8.len(s.text) or #s.text
		total = total + s.len
	end
	intro = {
		active = true,
		segments = segments,
		seg = 1,
		char = 0,
		acc = 0,
		pause = 0,
		key_cd = 0, -- throttle so the fast reveal doesn't machine-gun the keystroke sfx
		cps = math.max(1, total / INTRO_TYPING_SECONDS),
	}
	render_intro()
end

-- Reveal the whole intro at once and end the animation (skip / natural finish).
local function finish_intro()
	intro.active = false
	intro.seg = #intro.segments + 1
	render_intro()
	Audio.stop_group("typing")
end

local function advance_intro(dt)
	-- Hold on a paragraph pause before typing resumes.
	if intro.pause and intro.pause > 0 then
		intro.pause = intro.pause - dt
		if intro.pause > 0 then
			return
		end
		intro.pause = 0
	end

	intro.key_cd = math.max(0, intro.key_cd - dt)
	intro.acc = intro.acc + dt * intro.cps
	local changed = false
	while intro.active and intro.acc >= 1 do
		local s = intro.segments[intro.seg]
		if intro.char < s.len then
			intro.char = intro.char + 1
			intro.acc = intro.acc - 1
			changed = true
			if intro.key_cd <= 0 then
				Audio.play("type_key")
				intro.key_cd = 0.055
			end
		else
			-- Segment fully revealed; advance, honoring any pause it carries.
			intro.seg = intro.seg + 1
			intro.char = 0
			changed = true
			if intro.seg > #intro.segments then
				intro.active = false
			elseif s.pause_after and s.pause_after > 0 then
				intro.pause = s.pause_after
				break
			end
		end
	end
	if changed then
		render_intro()
	end
end

local function ctrl_or_cmd_down()
	return love.keyboard.isDown("lctrl")
		or love.keyboard.isDown("rctrl")
		or love.keyboard.isDown("lgui")
		or love.keyboard.isDown("rgui")
end

local function on_win(result_text)
	push_text(result_text, "system")

	local prev_time = best and best.best_time
	local prev_cmds = best and best.best_commands

	state.new_time_record = (prev_time == nil) or (state.win_time < prev_time)
	state.new_cmds_record = (prev_cmds == nil) or (state.win_commands < prev_cmds)

	best = {
		best_time = math.min(prev_time or math.huge, state.win_time),
		best_commands = math.min(prev_cmds or math.huge, state.win_commands),
	}
	save_best(best)

	Audio.play("win")
	if state.new_time_record then
		Audio.play("record")
	end
end

local function execute_input()
	clear_tab_state()
	local input = term.input
	term.input = ""
	term.cursor_pos = 0
	term.scroll = 0
	term.history_index = nil

	if input == "" then
		push_text("> ", "input")
		return
	end

	table.insert(term.history, input)
	push_text("> " .. input, "input")
	Audio.play("key_enter")

	local result = Commands.execute(state, input)
	if state.won then
		on_win(result or "")
	elseif result and result ~= "" then
		push_text(result, "output")
	end
	push_text("", "output")
end

local M = {}

-- Called by Screen.set("game"): kick off the CRT power-on intro. `start_new` /
-- `start_from_save` have already built `state`/`term` by this point.
function M.enter()
	-- Start (or restart) the CRT switch-on animation from t = 0.
	crt.active = true
	crt.mode = "on"
	crt.t = 0
	crt_swallow_text = false
	Audio.set_suppressed(state.terminal_only)
	Audio.play("crt_on")
	Audio.set_room(state.current_room)
end

-- Skip the running CRT animation. A power-on jumps straight to the live game; a
-- power-off jumps straight to the title. Called on any key / mouse press.
function M.crt_skip()
	if not crt.active then
		return
	end
	crt.active = false
	if crt.mode == "off" then
		Audio.stop_all()
		Screen.set("play")
	else
		Audio.stop_group("crt")
	end
end

-- Called by the `exit` command: play the CRT power-off, then go to the title.
-- (Any save has already happened in the command handler.)
function M.request_exit_to_play()
	crt.active = true
	crt.mode = "off"
	crt.t = 0
	Audio.stop_ambience() -- cut the room tone now, not when the power-off finishes
	Audio.play("crt_off")
end

-- Called by the `vim` / `nvim` / `vi` commands. Opening and closing both change
-- the layout (the editor takes the room panel, or half the window in
-- terminal-only mode), so each re-runs the layout and rewraps the terminal.
function M.open_vim()
	clear_tab_state()
	vim = Vim.open(state)
	vim_swallow_text = false
	Render.vim_open = true
	Render.resize(love.graphics.getDimensions())
	rewrap_terminal()
end

-- Called by vim.lua's :q / :wq.
function M.close_vim()
	vim = nil
	Render.vim_open = false
	Render.resize(love.graphics.getDimensions())
	rewrap_terminal()
end

-- Called by the bare `exit` command: freeze input and show the save prompt.
function M.begin_exit_prompt()
	clear_tab_state()
	exit_prompt.active = true
	push_text("Do you wish to save? (Y/n)", "system")
end

-- Resolve the exit prompt: "save" | "nosave" | "cancel".
local function resolve_exit_prompt(choice)
	exit_prompt.active = false
	if choice == "save" then
		Save.save_state(state, "save_data.txt")
		M.request_exit_to_play()
	elseif choice == "nosave" then
		M.request_exit_to_play()
	else
		-- cancel: drop back to the live terminal.
		push_text("Exit cancelled.", "system")
		push_text("", "output")
	end
end

function M.update(dt)
	Audio.update(dt)
	-- Clear the one-shot text-swallow (events for this frame already ran).
	crt_swallow_text = false
	-- Advance the CRT timer; on completion, a power-off hands off to the title.
	if crt.active then
		crt.t = crt.t + dt
		if crt.t >= crt.duration then
			crt.active = false
			if crt.mode == "off" then
				Audio.stop_all()
				Screen.set("play")
				return
			end
		end
	end
	if intro.active then
		advance_intro(dt)
	end
	if state.start_time and not state.won then
		state.elapsed = love.timer.getTime() - state.start_time
	end
	cursor_timer = cursor_timer + dt
	if cursor_timer > 0.5 then
		cursor_timer = 0
		term.cursor_visible = not term.cursor_visible
	end
  if state.exit_requested then
    Screen.set("save_prompt")
  end
end

function M.draw()
	local w, h = love.graphics.getDimensions()
	if w ~= Render.W or h ~= Render.H then
		Render.resize(w, h)
		rewrap_terminal()
	end
	-- While a CRT switch is active, render the frame through the effect: "on"
	-- runs progress 0->1, "off" runs 1->0. Otherwise draw normally.
	if crt.active then
		local frac = math.min(1, crt.t / crt.duration)
		local progress = (crt.mode == "off") and (1 - frac) or frac
		Render.draw_crt_power_on(progress, function()
			Render.draw(state, term, best, vim)
		end)
	else
		Render.draw(state, term, best, vim)
	end
end

function M.text_input(t)
	if crt.active then
		M.crt_skip()
		return
	end
	if crt_swallow_text then
		crt_swallow_text = false
		return
	end
	if intro.active then
		finish_intro()
		return
	end
	-- Editor open: it swallows all typing, including the keys that are commands
	-- in normal mode (see vim.lua).
	if vim then
		if vim_swallow_text then
			vim_swallow_text = false
		else
			Vim.text_input(vim, t)
		end
		return
	end
	if exit_prompt.active then
		return
	end
	if state.popup_item then
		return
	end
	if state.won then
		return
	end
	if t == "\t" then
		return
	end -- handled in keypressed
	clear_tab_state()
	local pos = term.cursor_pos or #term.input
	term.input = term.input:sub(1, pos) .. t .. term.input:sub(pos + 1)
	term.cursor_pos = pos + #t
	cursor_timer = 0
	term.cursor_visible = true
end

function M.keypressed(key)
	if crt.active then
		M.crt_skip()
		crt_swallow_text = true
		return
	end
	if intro.active then
		finish_intro()
		crt_swallow_text = true
		return
	end
	if vim then
		-- Editor text zoom, independent of the terminal's. Lasts the whole
		-- session (close and reopen keeps the size) but resets on new game /
		-- continue, since Render.vim_font_scale is reset by start_new /
		-- start_from_save.
		if ctrl_or_cmd_down() and (key == "=" or key == "kp+") then
			Render.set_vim_font_scale(Render.vim_font_scale + 0.1)
			vim_swallow_text = true
		elseif ctrl_or_cmd_down() and (key == "-" or key == "kp-") then
			Render.set_vim_font_scale(Render.vim_font_scale - 0.1)
			vim_swallow_text = true
		elseif ctrl_or_cmd_down() and key == "0" then
			Render.set_vim_font_scale(1)
			vim_swallow_text = true
		else
			Vim.keypressed(vim, key)
		end
		return
	end
	if exit_prompt.active then
		if key == "y" or key == "return" or key == "kpenter" then
			resolve_exit_prompt("save")
		elseif key == "n" then
			resolve_exit_prompt("nosave")
		elseif key == "escape" then
			resolve_exit_prompt("cancel")
		end
		crt_swallow_text = true
		return
	end
	if state.popup_item then
		if key == "escape" then
			Audio.play_sprite(state.popup_item.popup or state.popup_item.sprite, "close")
			Audio.duck(false)
			state.popup_item = nil
		elseif key == "up" or key == "pageup" then
			state.popup_page = math.max(1, (state.popup_page or 1) - 1)
			Audio.play("page_turn")
		elseif key == "down" or key == "pagedown" or key == "space" then
			state.popup_page = math.min(Render.popup_page_count or 1, (state.popup_page or 1) + 1)
			Audio.play("page_turn")
		end
		return
	end
	-- win screen: R restarts, Esc returns to the title
	if state.won then
		if key == "r" then
      M.start_new()
		elseif key == "escape" then
			M.request_exit_to_play()
		end
		return
	end

	if key == "return" or key == "kpenter" then
		execute_input()
	elseif key == "tab" then
		if term.tab_candidates then
			term.tab_index = (term.tab_index % #term.tab_candidates) + 1
			term.input = term.tab_candidates[term.tab_index]
			Audio.play("tab_many")
		else
			local candidates = Completion.get_completions(state, term.input)
			if #candidates == 1 then
				term.input = candidates[1]
				Audio.play("tab_one")
			elseif #candidates > 1 then
				-- Strip the already-typed prefix so we display only the completing part
				local disp_before = term.input:match("%s$") and term.input or (term.input:match("^(.*%s)%S+$") or "")
				local parts = {}
				for _, c in ipairs(candidates) do
					local display = c:sub(#disp_before + 1):match("^(.-)%s*$") or ""
					if display == "" then
						display = c:match("^(.-)%s*$") or c
					end
					table.insert(parts, display)
				end
				push_text(table.concat(parts, "  "), "completion")
				term.tab_candidates = candidates
				term.tab_index = 1
				term.input = candidates[1]
				Audio.play("tab_many")
			end
		end
		term.cursor_pos = #term.input
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "backspace" then
		clear_tab_state()
		local pos = term.cursor_pos or #term.input
		if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
			-- delete the word before the cursor
			local left = term.input:sub(1, pos)
			local s = left:gsub("%s*%S+%s*$", "")
			if s == left then
				s = ""
			end
			term.input = s .. term.input:sub(pos + 1)
			term.cursor_pos = #s
		elseif pos > 0 then
			-- delete the character before the cursor
			local left = term.input:sub(1, pos)
			local off = utf8.offset(left, -1) or 1
			term.input = left:sub(1, off - 1) .. term.input:sub(pos + 1)
			term.cursor_pos = off - 1
		end
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "w" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
		clear_tab_state()
		local pos = term.cursor_pos or #term.input
		local left = term.input:sub(1, pos)
		local s = left:gsub("%s*%S+%s*$", "")
		if s == left then
			s = ""
		end
		term.input = s .. term.input:sub(pos + 1)
		term.cursor_pos = #s
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "u" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
		clear_tab_state()
		local pos = term.cursor_pos or #term.input
		term.input = term.input:sub(pos + 1)
		term.cursor_pos = 0
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "left" then
		clear_tab_state()
		local pos = term.cursor_pos or #term.input
		if pos > 0 then
			local off = utf8.offset(term.input:sub(1, pos), -1) or 1
			term.cursor_pos = off - 1
		end
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "right" then
		clear_tab_state()
		local pos = term.cursor_pos or #term.input
		if pos < #term.input then
			local off = utf8.offset(term.input:sub(pos + 1), 2)
			term.cursor_pos = off and (pos + off - 1) or #term.input
		end
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "up" then
		clear_tab_state()
		if #term.history > 0 then
			if term.history_index == nil then
				term.history_index = #term.history
			else
				term.history_index = math.max(1, term.history_index - 1)
			end
			term.input = term.history[term.history_index]
			term.cursor_pos = #term.input
		end
	elseif key == "down" then
		clear_tab_state()
		if term.history_index then
			term.history_index = term.history_index + 1
			if term.history_index > #term.history then
				term.history_index = nil
				term.input = ""
			else
				term.input = term.history[term.history_index]
			end
			term.cursor_pos = #term.input
		end
	elseif key == "pageup" then
		term.scroll = term.scroll + 5
	elseif key == "pagedown" then
		term.scroll = math.max(0, term.scroll - 5)
	elseif key == "home" then
		term.scroll = math.max(0, #term.lines - 10)
	elseif key == "end" then
		term.scroll = 0
	elseif (key == "=" or key == "kp+") and ctrl_or_cmd_down() then
		if Render.set_font_scale(Render.font_scale + 0.1) then
			rewrap_terminal()
		end
	elseif (key == "-" or key == "kp-") and ctrl_or_cmd_down() then
		if Render.set_font_scale(Render.font_scale - 0.1) then
			rewrap_terminal()
		end
	elseif key == "0" and ctrl_or_cmd_down() then
		if Render.set_font_scale(1) then
			rewrap_terminal()
		end
	elseif key == "m" and ctrl_or_cmd_down() then
		state.minimap_hidden = not state.minimap_hidden
		push_text(state.minimap_hidden and "minimap hidden" or "minimap shown", "system")
	end
end

function M.mousepressed(x, y, button)
	if crt.active then
		M.crt_skip()
		return
	end
	if intro.active then
		finish_intro()
		return
	end
	if button ~= 1 or not state.popup_item then
		return
	end
	local function hit(r)
		return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
	end
	if hit(Render.popup_prev_rect) then
		state.popup_page = math.max(1, (state.popup_page or 1) - 1)
		Audio.play("page_turn")
	elseif hit(Render.popup_next_rect) then
		state.popup_page = math.min(Render.popup_page_count or 1, (state.popup_page or 1) + 1)
		Audio.play("page_turn")
	elseif hit(Render.popup_close_rect) then
		Audio.play_sprite(state.popup_item.popup or state.popup_item.sprite, "close")
		Audio.duck(false)
		state.popup_item = nil
	end
end

function M.start_new(terminal_only)
	state = World.new_state()
	state.terminal_only = terminal_only or false
	Render.terminal_only = state.terminal_only
	Audio.set_suppressed(state.terminal_only)
	-- A new run starts with an empty scratch pad (World.new_state) and the
	-- editor closed at its default text size.
	vim = nil
	Render.vim_open = false
	Render.set_vim_font_scale(1)
	Render.resize(love.graphics.getDimensions())
	term = {
		messages = {},
		lines = {},
		input = "",
		cursor_pos = 0,
		scroll = 0,
		cursor_visible = true,
		history = {},
		history_index = nil,
		tab_candidates = nil,
		tab_index = nil,
	}
	start_intro()
	best = load_best()
  M.state = state
end

function M.start_from_save(save_data)
  intro = { active = false } -- restored games skip the typewriter intro
  state = World.new_state()

  state.current_room = save_data.current_room
  state.previous_room = save_data.previous_room
  state.visited = save_data.visited
  state.files_read = save_data.files_read
  state.unlocked = save_data.unlocked
  state.destroyed = save_data.destroyed
  state.elapsed = save_data.elapsed
  state.command_count = save_data.command_count
  state.terminal_only = save_data.terminal_only or false
  state.start_time = love.timer.getTime() - state.elapsed
  -- Notes ride alongside the save in their own file, not inside save_data.txt.
  state.notes = Vim.load_notes()

  Render.terminal_only = state.terminal_only
  Audio.set_suppressed(state.terminal_only)
  vim = nil
  Render.vim_open = false
  Render.set_vim_font_scale(1)
  Render.resize(love.graphics.getDimensions())

  World.restore_rooms(save_data.rooms)

  term = {
    messages = {},
    lines = {},
    input = "",
    cursor_pos = 0,
    scroll = 0,
    cursor_visible = true,
    history = {},
    history_index = nil,
    tab_candidates = nil,
    tab_index = nil,
  }
  push_text("=== GAME RESTORED ===", "system")
  push_text("", "output")
  push_text(World.rooms[state.current_room].description, "output")
  push_text("", "output")
  best = load_best()
  M.state = state
end


M.resize = rewrap_terminal
return M
