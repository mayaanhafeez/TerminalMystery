-- screens/mode_select.lua
-- Display-mode picker, shown after "New Game" and before the game boots. Styled
-- like the boot terminal (monospace prompt, Rosé Pine palette, block cursor) but
-- WITHOUT the CRT overlay. The choice — full view vs. terminal-only — is baked
-- into the new game here and is never editable afterwards.
--
-- Selection is mouse-position driven, the same way play.lua works: the arrow
-- follows whichever option the mouse is over, and keyboard nav moves the OS
-- cursor onto a row so the two stay in sync.

Screen = require("screen")
Render = require("render")

local M = {}

local PROMPT = "guest@strictly.ai:~$ "

-- Rosé Pine palette (matches boot.lua).
local C_BG = { 0.098, 0.090, 0.141, 1 } -- base #191724
local C_PROMPT = { 0.42, 0.50, 0.78 } -- muted blue
local C_CMD = { 0.76, 0.82, 1.00 } -- light blue-white
local C_OUT = { 0.50, 0.60, 0.88 } -- soft blue
local C_ACCENT = { 0.612, 0.812, 0.847 } -- foam #9ccfd8 (selected option)
local C_DIM = { 0.36, 0.42, 0.62 } -- unselected option

-- The two choices. `terminal_only` is what gets handed to the new game.
local OPTIONS = {
	{ key = "1", title = "Full view", blurb = "terminal + live room view", terminal_only = false },
	{ key = "2", title = "Terminal only", blurb = "just the shell, no room view", terminal_only = true },
}

local PAD_X = 48

local selected = 1
local cursor_timer = 0
local cursor_on = true

-- Geometry shared by draw and hit-testing, recomputed each call so it tracks
-- window resizes. Returns the font, the y where each option row sits, and a
-- clickable hitbox (x/y/w/h) + center (cx/cy) per option.
local function layout()
	local w, h = love.graphics.getDimensions()
	local font = Render.font_mono_big or Render.font_mono or Render.font
	local line_h = font:getHeight() * 1.5
	-- Header block: prompt line (1.4), "Choose…" (1.0), permanent line (1.6).
	local options_top = h * 0.26 + line_h * 4.0
	local rows = {}
	for i, opt in ipairs(OPTIONS) do
		local label = "> [" .. opt.key .. "] " .. opt.title -- "> " marker for width
		local text_w = font:getWidth(label) + font:getWidth("   ") + font:getWidth(opt.blurb)
		local y = options_top + (i - 1) * line_h
		-- The hitbox fills the whole row line so clicking anywhere on it lands.
		local pad_top = (line_h - font:getHeight()) / 2
		rows[i] = {
			text_y = y,
			x = PAD_X,
			y = y - pad_top,
			w = text_w + font:getWidth("MM"), -- a little slack past the text
			h = line_h,
			cx = PAD_X + text_w / 2,
			cy = y + font:getHeight() / 2,
		}
	end
	return { font = font, line_h = line_h, rows = rows, w = w, h = h }
end

-- Index of the option the mouse is currently over, or nil.
local function option_at(mx, my)
	local L = layout()
	for i, r in ipairs(L.rows) do
		if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
			return i
		end
	end
	return nil
end

function M.enter()
	selected = 1
	cursor_timer = 0
	cursor_on = true
end

local function confirm()
	local opt = OPTIONS[selected]
	GameScreen.start_new(opt.terminal_only)
	Screen.set("game")
end

-- Move the OS cursor onto an option's center so mouse-hover and `selected` agree
-- (mirrors how play.lua drives its buttons from the keyboard).
local function focus(index)
	selected = index
	local L = layout()
	local r = L.rows[index]
	if r then
		love.mouse.setPosition(r.cx, r.cy)
	end
end

function M.update(dt)
	cursor_timer = cursor_timer + dt
	if cursor_timer > 0.45 then
		cursor_timer = 0
		cursor_on = not cursor_on
	end
	-- Arrow follows the mouse: if it's over a row, that row becomes selected.
	-- Off the rows, the last selection sticks (so keyboard focus persists).
	local hov = option_at(love.mouse.getPosition())
	if hov then
		selected = hov
	end
end

function M.keypressed(key)
	if key == "up" or key == "k" then
		focus(selected == 1 and #OPTIONS or selected - 1)
	elseif key == "down" or key == "j" then
		focus(selected == #OPTIONS and 1 or selected + 1)
	elseif key == "1" then
		focus(1)
	elseif key == "2" then
		focus(2)
	elseif key == "return" or key == "kpenter" then
		confirm()
	elseif key == "escape" then
		Screen.set("play_menu")
	end
end

function M.mousepressed(x, y, button)
	if button ~= 1 then
		return
	end
	-- Clicking an option selects it and confirms; clicks off the rows do nothing.
	local idx = option_at(x, y)
	if idx then
		selected = idx
		confirm()
	end
end

function M.draw()
	local L = layout()
	local font, line_h = L.font, L.line_h
	love.graphics.setColor(C_BG)
	love.graphics.rectangle("fill", 0, 0, L.w, L.h)

	love.graphics.setFont(font)
	local y = L.h * 0.26

	-- Fake command line at the top.
	love.graphics.setColor(C_PROMPT)
	love.graphics.print(PROMPT, PAD_X, y)
	love.graphics.setColor(C_CMD)
	love.graphics.print("./configure --display", PAD_X + font:getWidth(PROMPT), y)
	y = y + line_h * 1.4

	love.graphics.setColor(C_OUT)
	love.graphics.print("Choose a display mode for this case.", PAD_X, y)
	y = y + line_h
	love.graphics.setColor(C_DIM)
	love.graphics.print("This choice is permanent and can't be changed later.", PAD_X, y)

	-- The selectable options, positioned from the shared layout.
	for i, opt in ipairs(OPTIONS) do
		local r = L.rows[i]
		local is_sel = (i == selected)
		local marker = is_sel and "> " or "  "
		local label = marker .. "[" .. opt.key .. "] " .. opt.title
		love.graphics.setColor(is_sel and C_ACCENT or C_DIM)
		love.graphics.print(label, PAD_X, r.text_y)
		-- Blurb, indented past the label, dimmer.
		local bx = PAD_X + font:getWidth(label) + font:getWidth("   ")
		love.graphics.setColor(is_sel and C_OUT or C_DIM)
		love.graphics.print(opt.blurb, bx, r.text_y)
		-- Block cursor trailing the selected row.
		if is_sel and cursor_on then
			local cx = bx + font:getWidth(opt.blurb) + 6
			love.graphics.setColor(C_ACCENT)
			love.graphics.rectangle("fill", cx, r.text_y, font:getWidth("M"), font:getHeight())
		end
	end

	-- Footer hint.
	local hf = Render.font_mono or Render.font
	love.graphics.setFont(hf)
	love.graphics.setColor(C_DIM)
	local hint = "up/down, j/k or mouse to move  ·  enter or click to confirm  ·  esc to go back"
	love.graphics.print(hint, PAD_X, L.h - 72)
	love.graphics.setColor(1, 1, 1, 1)
end

return M
