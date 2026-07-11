local World = require("world")
local utf8 = require("utf8")
local Commands = require("commands")
local Render = require("render")
local Completion = require("commands.completion")
local Screen = require("screen")

local state
local term
local best
local cursor_timer = 0
local INTRO = [[=== TERMINAL MYSTERY ===

Strictly.ai just closed its Series C. At the launch party in the
CEO's house, Arjun Mehta — VP of AI Research — is found dead in
the Den, an empty bottle of kombucha beside him.

Legal wants it kept quiet until you've had a look. Four engineers
were in range of the Den during the window, and one of them is
still here.

You stand in the Entrance Hall. Type `help` to see what you can
do. When you are certain, type `accuse <name>` to make your case.]]

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

	local result = Commands.execute(state, input)
	if state.won then
		on_win(result or "")
	elseif result and result ~= "" then
		push_text(result, "output")
	end
	push_text("", "output")
end

local M = {}

function M.update(dt)
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
	Render.draw(state, term, best)
end

function M.text_input(t)
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
	if state.popup_item then
		if key == "escape" then
			state.popup_item = nil
		elseif key == "up" or key == "pageup" then
			state.popup_page = math.max(1, (state.popup_page or 1) - 1)
		elseif key == "down" or key == "pagedown" or key == "space" then
			state.popup_page = math.min(Render.popup_page_count or 1, (state.popup_page or 1) + 1)
		end
		return
	end
	-- win screen: only R
	if state.won then
		if key == "r" then
      M.start_new()
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
	end
end

function M.mousepressed(x, y, button)
	if button ~= 1 or not state.popup_item then
		return
	end
	local function hit(r)
		return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
	end
	if hit(Render.popup_prev_rect) then
		state.popup_page = math.max(1, (state.popup_page or 1) - 1)
	elseif hit(Render.popup_next_rect) then
		state.popup_page = math.min(Render.popup_page_count or 1, (state.popup_page or 1) + 1)
	elseif hit(Render.popup_close_rect) then
		state.popup_item = nil
	end
end

function M.start_new()
	state = World.new_state()
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
	push_text(INTRO, "system")
	push_text("", "output")
	push_text(World.rooms.foyer.description, "output")
	push_text("", "output")
	best = load_best()
  M.state = state
end

function M.start_from_save(save_data)
  state = World.new_state()

  state.current_room = save_data.current_room
  state.previous_room = save_data.previous_room
  state.visited = save_data.visited
  state.files_read = save_data.files_read
  state.unlocked = save_data.unlocked
  state.destroyed = save_data.destroyed
  state.elapsed = save_data.elapsed
  state.command_count = save_data.command_count
  state.start_time = love.timer.getTime() - state.elapsed

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
