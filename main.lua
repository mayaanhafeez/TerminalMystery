-- main.lua
-- LÖVE callbacks, input handling, save-file I/O. The thin glue layer that
-- ties world.lua, commands.lua and render.lua together.

local utf8 = require("utf8")
local World = require("world")
local Commands = require("commands")
local Render = require("render")
local Completion = require("commands.completion")

local state -- game state from World.new_state()
local term -- terminal UI state (input/lines/scroll/history)
local best -- personal best loaded from save (or nil)
local cursor_timer = 0

local INTRO = [[=== TERMINAL MYSTERY ===

It is the autumn of 1923. Lord Edmund Ashworth lies dead in his
Study at Ashworth Manor — a single drop of foam at the corner
of his mouth, a half-finished glass of brandy on the desk.

The constabulary is two hours away by motorcar. You are the
nearest investigator. The killer is still in the house.

You stand in the Foyer. Type `help` to see what you can do.
When you are certain, type `accuse <name>` to make your case.]]

-- ---------- save file ----------

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

-- ---------- terminal helpers ----------

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

local function ctrl_or_cmd_down()
	return love.keyboard.isDown("lctrl")
		or love.keyboard.isDown("rctrl")
		or love.keyboard.isDown("lgui")
		or love.keyboard.isDown("rgui")
end

local function init_game()
	state = World.new_state()
	term = {
		messages = {},
		lines = {},
		input = "",
		scroll = 0,
		cursor_visible = true,
		history = {},
		history_index = nil,
		tab_candidates = nil,
		tab_index = nil,
	}
	push_text(INTRO, "system")
	push_text("", "output")
	push_text(World.rooms.foyer.description, "output")
	push_text("", "output")
	best = load_best()
end

-- ---------- LÖVE callbacks ----------

function love.load()
	love.keyboard.setKeyRepeat(true)
	Render.load()
	init_game()
end

function love.update(dt)
	if state.start_time and not state.won then
		state.elapsed = love.timer.getTime() - state.start_time
	end
	cursor_timer = cursor_timer + dt
	if cursor_timer > 0.5 then
		cursor_timer = 0
		term.cursor_visible = not term.cursor_visible
	end
end

function love.draw()
	local w, h = love.graphics.getDimensions()
	if w ~= Render.W or h ~= Render.H then
		Render.resize(w, h)
		rewrap_terminal()
	end
	Render.draw(state, term, best)
end

function love.resize(w, h)
	Render.resize(w, h)
	rewrap_terminal()
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
end

local function execute_input()
	clear_tab_state()
	local input = term.input
	term.input = ""
	term.scroll = 0
	term.history_index = nil

	if input == "" then
		push_text("> ", "input")
		return
	end

	table.insert(term.history, input)
	push_text("> " .. input, "input")

	local result = Commands.execute(state, input)
	if state.won then
		on_win(result or "")
	elseif result and result ~= "" then
		push_text(result, "output")
	end
	push_text("", "output")
end

function love.textinput(t)
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
	term.input = term.input .. t
	cursor_timer = 0
	term.cursor_visible = true
end

function love.keypressed(key)
	if state.popup_item then
		if key == "escape" then
			state.popup_item = nil
		end
		return
	end
	-- win screen: only R
	if state.won then
		if key == "r" then
			init_game()
		end
		return
	end

	if key == "return" or key == "kpenter" then
		execute_input()
	elseif key == "tab" then
		if term.tab_candidates then
			term.tab_index = (term.tab_index % #term.tab_candidates) + 1
			term.input = term.tab_candidates[term.tab_index]
		else
			local candidates = Completion.get_completions(state, term.input)
			if #candidates == 1 then
				term.input = candidates[1]
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
			end
		end
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "backspace" then
		clear_tab_state()
		if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
			local s = term.input:gsub("%s*%S+%s*$", "")
			if s == term.input then
				s = ""
			end
			term.input = s
			cursor_timer = 0
			term.cursor_visible = true
		else
			local off = utf8.offset(term.input, -1)
			if off then
				term.input = term.input:sub(1, off - 1)
			end
		end
	elseif key == "w" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
		clear_tab_state()
		local s = term.input:gsub("%s*%S+%s*$", "")
		if s == term.input then
			s = ""
		end
		term.input = s
		cursor_timer = 0
		term.cursor_visible = true
	elseif key == "u" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
		clear_tab_state()
		term.input = ""
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
	end
end

function love.mousepressed(x, y, button)
	if button == 1 and state.popup_item and Render.popup_close_rect then
		local r = Render.popup_close_rect
		if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
			state.popup_item = nil
		end
	end
end
