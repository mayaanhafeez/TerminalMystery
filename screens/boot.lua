-- screens/boot.lua
-- Startup boot animation. A fake terminal types out a couple of bash commands,
-- prints a few status lines, then renders an ASCII-art "TERMINAL MYSTERY"
-- banner before handing off to the "play" title screen. Plays once at app
-- launch. Any key / click skips. Palette matches the title (Rosé Pine) so the
-- hand-off into the indigo/purple title screen is seamless.

Screen = require("screen")
Render = require("render")

local M = {}

local PROMPT = "guest@strictly.ai:~$ "

-- ASCII-art banner (figlet "standard"), stacked TERMINAL over MYSTERY.
local ART = {
	" _____ _____ ____  __  __ ___ _   _    _    _     ",
	"|_   _| ____|  _ \\|  \\/  |_ _| \\ | |  / \\  | |    ",
	"  | | |  _| | |_) | |\\/| || ||  \\| | / _ \\ | |    ",
	"  | | | |___|  _ <| |  | || || |\\  |/ ___ \\| |___ ",
	"  |_| |_____|_| \\_\\_|  |_|___|_| \\_/_/   \\_\\_____|",
	"                                                  ",
	" __  ____   ______ _____ _____ ______   __",
	"|  \\/  \\ \\ / / ___|_   _| ____|  _ \\ \\ / /",
	"| |\\/| |\\ V /\\___ \\ | | |  _| | |_) \\ V / ",
	"| |  | | | |  ___) || | | |___|  _ < | |  ",
	"|_|  |_| |_| |____/ |_| |_____|_| \\_\\|_|  ",
}

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
	for _, line in ipairs(ART) do
		s[#s + 1] = { art = line, delay = 0.05 }
	end
	s[#s + 1] = { blank = true }
	s[#s + 1] = { out = "booting...", delay = 0.25 }
	return s
end

local SCRIPT = build_script()

local CHAR_INTERVAL = 0.024 -- seconds per typed character
local CMD_PAUSE = 0.26 -- pause after a command finishes typing (the "enter")
local LINE_DELAY = 0.085 -- default pause before an output line prints
local BLANK_DELAY = 0.12 -- pause for a spacer line
local END_HOLD = 0.8 -- hold on the finished banner before handing off

-- Rosé Pine palette (matches the title screen).
local C_BG = { 0.098, 0.090, 0.141, 1 } -- base #191724
local C_PROMPT = { 0.431, 0.416, 0.525 } -- muted #6e6a86
local C_CMD = { 0.878, 0.871, 0.957 } -- text #e0def4
local C_OUT = { 0.565, 0.549, 0.667 } -- subtle #908caa
local C_ART = { 0.612, 0.812, 0.847 } -- foam #9ccfd8
local C_CURSOR = { 0.878, 0.871, 0.957 }

-- Animation state (rebuilt in M.enter):
--   idx          -- current SCRIPT entry being processed
--   char         -- chars of the current command revealed so far
--   timer        -- accumulates dt to pace typing / line delays
--   hold         -- accumulates dt on the finished banner before handoff
--   rendered     -- committed lines to draw, each { text, kind = cmd|out|art }
--   cursor_timer -- blink accumulator
--   cursor_on    -- block-cursor visibility
local anim = {}

function M.enter()
	anim = {
		idx = 1,
		char = 0,
		timer = 0,
		hold = 0,
		rendered = {},
		cursor_timer = 0,
		cursor_on = true,
	}
end

function M.update(dt)
	-- Cursor blink.
	anim.cursor_timer = anim.cursor_timer + dt
	if anim.cursor_timer > 0.45 then
		anim.cursor_timer = 0
		anim.cursor_on = not anim.cursor_on
	end

	-- Whole script rendered: hold on the banner, then go to the title.
	if anim.idx > #SCRIPT then
		if not anim._shot then -- DEBUG: capture one banner frame
			anim._shot = true
			love.graphics.captureScreenshot("boot_shot.png")
		end
		anim.hold = anim.hold + dt
		if anim.hold > END_HOLD then
			Screen.set("play")
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
		-- Output / banner / spacer line: wait its delay, then print it whole.
		local delay = e.blank and BLANK_DELAY or (e.delay or LINE_DELAY)
		if anim.timer >= delay then
			local text = e.art or (e.blank and "" or e.out)
			local kind = e.art and "art" or "out"
			table.insert(anim.rendered, { text = text, kind = kind })
			anim.idx = anim.idx + 1
			anim.timer = 0
		end
	end
end

function M.draw()
	local w, h = love.graphics.getDimensions()
	love.graphics.clear(C_BG)

	local font = Render.font_mono or Render.font
	love.graphics.setFont(font)
	local line_h = font:getHeight() * 1.35
	local pad_x, pad_y = 44, 40

	-- Committed lines plus the line currently being typed (or the final prompt).
	local display = {}
	for _, r in ipairs(anim.rendered) do
		display[#display + 1] = r
	end
	local active = nil
	if anim.idx <= #SCRIPT and SCRIPT[anim.idx].cmd then
		active = { text = PROMPT .. SCRIPT[anim.idx].cmd:sub(1, anim.char), kind = "cmd" }
		display[#display + 1] = active
	elseif anim.idx > #SCRIPT then
		active = { text = PROMPT, kind = "cmd" }
		display[#display + 1] = active
	end

	-- Scroll: only draw the last screenful of lines.
	local max_lines = math.max(1, math.floor((h - pad_y * 2) / line_h))
	local start = math.max(1, #display - max_lines + 1)

	local y = pad_y
	for i = start, #display do
		local entry = display[i]
		if entry.kind == "cmd" then
			-- Prompt drawn dim, the typed command bright.
			local plen = #PROMPT
			local ptext = entry.text:sub(1, plen)
			local ctext = entry.text:sub(plen + 1)
			love.graphics.setColor(C_PROMPT)
			love.graphics.print(ptext, pad_x, y)
			love.graphics.setColor(C_CMD)
			love.graphics.print(ctext, pad_x + font:getWidth(ptext), y)
		elseif entry.kind == "art" then
			love.graphics.setColor(C_ART)
			love.graphics.print(entry.text, pad_x, y)
		else
			love.graphics.setColor(C_OUT)
			love.graphics.print(entry.text, pad_x, y)
		end
		-- Blinking block cursor on the active (last) line.
		if entry == active and anim.cursor_on then
			local cx = pad_x + font:getWidth(entry.text) + 2
			love.graphics.setColor(C_CURSOR)
			love.graphics.rectangle("fill", cx, y, font:getWidth("M"), font:getHeight())
		end
		y = y + line_h
	end

	love.graphics.setColor(1, 1, 1, 1)
end

function M.keypressed(_)
	Screen.set("play")
end

function M.mousepressed(_, _, _)
	Screen.set("play")
end

return M
