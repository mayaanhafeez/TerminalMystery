-- screens/boot.lua
-- Startup boot animation. A fake terminal types a couple of bash commands and
-- status lines, then reveals the "TERMINAL MYSTERY" ASCII banner. A steady CRT
-- filter sits over the whole screen; when the banner is up, a white "flashbang"
-- whites out and hands off to the play/title screen (which fades the flash out
-- and shows the same banner as its title). Any key / click skips.

Screen = require("screen")
Render = require("render")
Banner = require("banner")
local Audio = require("audio")

local M = {}

local PROMPT = "guest@strictly.ai:~$ "

-- Build the scripted sequence: two commands + status lines, then the banner.
--   { cmd = "..." }  -- a command typed char by char
--   { out = "..." }  -- a status line printed whole
--   { art = "..." }  -- one line of the ASCII banner
--   { blank = true } -- a spacer line
local function build_script()
	local s = {
		{ cmd = "ssh guest@strictly.ai" },
		{ out = "Connected. Case file: incident-arjun", delay = 0.35 },
		{ cmd = "./start.sh" },
		{ out = "Decrypting evidence... ok", delay = 0.3 },
		{ out = "Loading scene: 6 rooms  4 suspects  1 victim" },
		{ blank = true },
	}
	for _, line in ipairs(Banner.lines) do
		s[#s + 1] = { art = line, delay = 0.06 }
	end
	return s
end

local SCRIPT = build_script()

local CHAR_INTERVAL = 0.024 -- seconds per typed character
local CMD_PAUSE = 0.26 -- pause after a command finishes typing (the "enter")
local LINE_DELAY = 0.085 -- default pause before an output line prints
local BLANK_DELAY = 0.12 -- pause for a spacer line

-- Rosé Pine palette (matches the title screen).
local C_BG = { 0.098, 0.090, 0.141, 1 } -- base #191724
local C_PROMPT = { 0.42, 0.50, 0.78 } -- muted blue
local C_CMD = { 0.76, 0.82, 1.00 } -- light blue-white
local C_OUT = { 0.50, 0.60, 0.88 } -- soft blue
local C_ART = { 0.612, 0.812, 0.847 } -- foam #9ccfd8 (banner; matches play)
local C_CURSOR = { 0.76, 0.82, 1.00 }

-- Animation state (rebuilt in M.enter):
--   idx          -- current SCRIPT entry being processed
--   char         -- chars of the current command revealed so far
--   timer        -- accumulates dt to pace typing / line delays
--   ready        -- true once the banner is fully shown (awaiting a keypress)
--   flashing     -- true once the flashbang has begun
--   rendered     -- committed lines, each { text, kind = cmd|out|art }
--   cursor_timer -- blink accumulator
--   cursor_on    -- block-cursor visibility
local anim = {}

function M.enter()
	anim = {
		idx = 1,
		char = 0,
		timer = 0,
		ready = false,
		flashing = false,
		rendered = {}, -- committed console lines (cmd/out)
		art_shown = 0, -- banner lines revealed so far
		cursor_timer = 0,
		cursor_on = true,
	}
end

-- Jump the animation straight to its finished state: every console line and the
-- full banner shown, awaiting the "press any key to continue" keypress.
local function finish_boot()
	anim.rendered = {}
	local art_count = 0
	for _, e in ipairs(SCRIPT) do
		if e.art then
			art_count = art_count + 1
		elseif e.cmd then
			table.insert(anim.rendered, { text = PROMPT .. e.cmd, kind = "cmd" })
		else
			table.insert(anim.rendered, { text = e.blank and "" or e.out, kind = "out" })
		end
	end
	anim.art_shown = art_count
	anim.idx = #SCRIPT + 1
	anim.char = 0
	anim.ready = true
end

-- Any key / click: first press fast-forwards to the finished banner; once it's
-- ready, the next press begins the flashbang hand-off to the title screen.
local function on_input()
	if anim.flashing then
		return
	elseif not anim.ready then
		Audio.stop_group("typing")
		Audio.stop_group("crt")
		finish_boot()
	else
		anim.flashing = true
		Audio.play("crt_on")
		Render.flash_begin()
	end
end

function M.update(dt)
	-- Cursor blink.
	anim.cursor_timer = anim.cursor_timer + dt
	if anim.cursor_timer > 0.45 then
		anim.cursor_timer = 0
		anim.cursor_on = not anim.cursor_on
	end

	-- Whole script rendered: wait for the player to continue (see on_input).
	if anim.idx > #SCRIPT then
		anim.ready = true
		if anim.flashing and Render.flash_update(dt) == "switch" then
			Screen.set("play") -- title fades the flash out and shows the banner
		end
		return
	end

	anim.timer = anim.timer + dt
	local e = SCRIPT[anim.idx]

	if e.cmd then
		-- Reveal one character per keystroke interval.
		local n = #e.cmd
		while anim.char < n and anim.timer >= CHAR_INTERVAL do
			anim.timer = anim.timer - CHAR_INTERVAL
			anim.char = anim.char + 1
		end
		-- Fully typed: pause, then commit the line and advance.
		if anim.char >= n and anim.timer >= CMD_PAUSE then
			table.insert(anim.rendered, { text = PROMPT .. e.cmd, kind = "cmd" })
			anim.idx = anim.idx + 1
			anim.char = 0
			anim.timer = 0
		end
	else
		-- Output / banner / spacer line: wait its delay, then commit it. Banner
		-- lines feed the centered title banner; console lines feed the log.
		local delay = e.blank and BLANK_DELAY or (e.delay or LINE_DELAY)
		if anim.timer >= delay then
			if e.art then
				anim.art_shown = anim.art_shown + 1
			else
				table.insert(anim.rendered, { text = e.blank and "" or e.out, kind = "out" })
			end
			anim.idx = anim.idx + 1
			anim.timer = 0
		end
	end
end

local function draw_content()
	local w, h = love.graphics.getDimensions()
	love.graphics.setColor(C_BG)
	love.graphics.rectangle("fill", 0, 0, w, h)

	-- The banner sits at the shared title position (same as the play screen), so
	-- the flashbang hand-off keeps it fixed. It reveals line-by-line; the block
	-- reserves its full height from the start so the console below stays put.
	local banner_bottom = Render.draw_title_banner(w, h, C_ART, anim.art_shown)

	-- Console log (typed commands + status) below the banner.
	local font = Render.font_mono_big or Render.font_mono or Render.font
	love.graphics.setFont(font)
	local line_h = font:getHeight() * 1.35
	local pad_x = 48
	local y = banner_bottom + 44

	local display = {}
	for _, r in ipairs(anim.rendered) do
		display[#display + 1] = r
	end
	local active = nil
	if anim.idx <= #SCRIPT and SCRIPT[anim.idx].cmd then
		active = { text = PROMPT .. SCRIPT[anim.idx].cmd:sub(1, anim.char), kind = "cmd" }
		display[#display + 1] = active
	end

	for _, entry in ipairs(display) do
		if entry.kind == "cmd" then
			-- Prompt drawn dim, the typed command bright.
			local plen = #PROMPT
			local ptext = entry.text:sub(1, plen)
			local ctext = entry.text:sub(plen + 1)
			love.graphics.setColor(C_PROMPT)
			love.graphics.print(ptext, pad_x, y)
			love.graphics.setColor(C_CMD)
			love.graphics.print(ctext, pad_x + font:getWidth(ptext), y)
		else
			love.graphics.setColor(C_OUT)
			love.graphics.print(entry.text, pad_x, y)
		end
		-- Blinking block cursor on the active (typing) line.
		if entry == active and anim.cursor_on then
			local cx = pad_x + font:getWidth(entry.text) + 2
			love.graphics.setColor(C_CURSOR)
			love.graphics.rectangle("fill", cx, y, font:getWidth("M"), font:getHeight())
		end
		y = y + line_h
	end

	-- Once the banner is up, prompt the player to continue (blinking).
	if anim.ready and not anim.flashing and anim.cursor_on then
		local hint = "press any key to continue"
		local hf = Render.font_mono or Render.font
		love.graphics.setFont(hf)
		love.graphics.setColor(C_OUT)
		love.graphics.print(hint, (w - hf:getWidth(hint)) / 2, h - 72)
	end
	love.graphics.setColor(1, 1, 1, 1)
end

function M.draw()
	-- Boot content through the steady CRT filter, flashbang on top.
	Render.draw_crt_overlay(draw_content)
	Render.draw_intro_flash()
end

function M.keypressed(_)
	on_input()
end

function M.mousepressed(_, _, _)
	on_input()
end

return M
