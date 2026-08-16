-- render.lua
-- All drawing. Two panels (terminal left, room-view right) + status bar + win overlay.

local World = require("world")
local utf8 = require("utf8")
local Banner = require("banner")
local Vim = require("vim")
local M = {}

-- The room view (right panel) is drawn at a fixed virtual resolution into an
-- offscreen canvas and then scaled uniformly to a rect that preserves that
-- aspect ratio. The split between the terminal panel (left) and the room
-- panel is recomputed in M.resize so the room fits the available height
-- without letterbox bars; the terminal takes whatever width is left over and
-- reflows its text. Status bar spans the full window at the bottom.
local ROOM_VW = 520
-- Height is a 2:3 multiple of the width (520 * 9/6) so the 6x9 tile grid fills
-- the canvas exactly with square tiles — no bare strip along one edge.
local ROOM_VH = 780
local ROOM_ASPECT = ROOM_VW / ROOM_VH
local MIN_TERM_W = 280

M.W = 1280
M.H = 800
M.STATUS_H = 28 -- recomputed from the terminal font height in load_terminal_font
M.STATUS_PAD_V = 6 -- vertical padding above+below the status text
M.TERM_W = 760
M.MAP_X = 760
M.MAP_W = 520
M.PAD = 14

-- On-screen rect where the room canvas is blitted (set by M.resize).
M.room_x = 760
M.room_y = 0
M.room_w = 520
M.room_h = 780

-- When true the room panel is dropped entirely and the terminal takes the whole
-- window width. Chosen once per game on the mode-select screen and never toggled
-- afterwards; the game screen sets it before the first resize/rewrap.
M.terminal_only = false

-- True while the notes editor is open. It takes over the room panel in normal
-- mode; in terminal-only mode there is no room panel, so the window splits in
-- half instead. The game screen toggles this, then re-runs resize + rewraps.
M.vim_open = false
M.vim_x, M.vim_y, M.vim_w, M.vim_h = 0, 0, 0, 0

function M.resize(w, h)
	M.W = w
	M.H = h
	-- Terminal-only mode: no room panel, terminal spans the full width — unless
	-- vim is open, which splits the window down the middle.
	if M.terminal_only then
		M.room_w = 0
		M.room_h = math.max(1, h - M.STATUS_H)
		M.TERM_W = M.vim_open and math.floor(w / 2) or w
		M.MAP_X = w
		M.MAP_W = 0
		M.room_x = w
		M.room_y = 0
		M.vim_x, M.vim_y = M.TERM_W, 0
		M.vim_w, M.vim_h = w - M.TERM_W, math.max(1, h - M.STATUS_H)
		return
	end
	local avail_h = math.max(1, h - M.STATUS_H)
	-- The room ALWAYS fills the full panel height so no letterbox bars ever
	-- appear around it. It keeps its aspect ratio and the terminal takes the
	-- remaining width — so a narrower window shrinks the terminal, not the room.
	-- Only when the window is too narrow to give the terminal its minimum width
	-- do we cap the room width (it still fills the height, squishing slightly
	-- rather than showing bars).
	local room_h = avail_h
	local room_w = math.min(room_h * ROOM_ASPECT, math.max(1, w - MIN_TERM_W))
	M.room_w = room_w
	M.room_h = room_h
	M.TERM_W = w - room_w
	M.MAP_X = M.TERM_W
	M.MAP_W = room_w
	M.room_x = M.TERM_W
	M.room_y = 0
	-- vim takes the room panel's slot verbatim; the room view isn't drawn at all
	-- while it's open.
	M.vim_x, M.vim_y = M.room_x, M.room_y
	M.vim_w, M.vim_h = M.room_w, M.room_h
end

-- Palette
local C = {
	-- Terminal palette matches the boot + mode-select screens (Rosé Pine).
	bg = { 0.098, 0.090, 0.141 }, -- base #191724
	term_bg = { 0.098, 0.090, 0.141 }, -- base #191724
	term_text = { 0.50, 0.60, 0.88 }, -- soft blue (output)
	term_dim = { 0.36, 0.42, 0.62 }, -- dim blue (completions)
	term_user = { 0.76, 0.82, 1.00 }, -- light blue-white (typed input)
	prompt = { 0.42, 0.50, 0.78 }, -- muted blue
	system = { 0.612, 0.812, 0.847 }, -- foam accent (system lines)
	map_bg = { 0.10, 0.12, 0.16 },
	map_border = { 0.16, 0.18, 0.22 },
	room_unvisited = { 0.18, 0.20, 0.24 },
	room_visited = { 0.32, 0.36, 0.44 },
	room_current = { 0.95, 0.70, 0.25 },
	room_text_dim = { 0.40, 0.42, 0.48 },
	room_text = { 0.88, 0.88, 0.92 },
	room_text_curr = { 0.10, 0.10, 0.10 },
	status_bg = { 0.122, 0.114, 0.180 }, -- surface #1f1d2e
	status_text = { 0.68, 0.70, 0.82 }, -- subtle blue-grey
	connection = { 0.42, 0.45, 0.55 },
	win_overlay = { 0, 0, 0, 0.88 },
	win_title = { 0.95, 0.85, 0.45 },
	win_text = { 0.90, 0.95, 0.90 },
	win_record = { 0.95, 0.50, 0.50 },
	-- Item glow & label
	item_box = { 0.90, 0.70, 0.20 },
	item_box_border = { 0.70, 0.50, 0.10 },
	item_label = { 1.00, 0.95, 0.70 },
}

local LINE_COLOURS = {
	input = C.term_user,
	system = C.system,
	error = C.win_record,
	completion = C.term_dim,
}

M.font = nil -- popup + win screen (terminal font, fixed size)
M.font_term = nil -- terminal panel + status bar (scaled by M.font_scale)
M.font_big = nil -- headings / menu / title buttons (terminal font)
M.font_small = nil -- terminal font, small
M.font_room = nil -- room view item labels (pixel/Minecraft font)
M.font_room_big = nil -- room view name banner (pixel font)
M.font_room_small = nil -- room view minimap labels (pixel font)
M.font_mono = nil -- computer-log font (laptop/chat popups); loaded from font_mono.ttf
M.font_mono_big = nil -- larger monospace for the boot screen / ASCII banner
M.font_handwriting = nil -- loaded from handwriting.ttf if present
M.font_handwriting_large = nil -- large variant for titles
M.font_scale = 1 -- multiplier on M.font_term; adjusted via M.set_font_scale
M.font_vim = nil -- the notes editor's own font (vim.lua pane)
M.vim_font_scale = 1 -- multiplier on M.font_vim; adjusted via M.set_vim_font_scale
M.popup_close_rect = nil -- set each frame popup is drawn; nil otherwise
M.popup_prev_rect = nil -- previous-page hit rect (paginated popups); nil otherwise
M.popup_next_rect = nil -- next-page hit rect (paginated popups); nil otherwise
M.popup_page_count = 1 -- number of pages in the current popup (1 = no pagination)
M.room_canvas = nil -- offscreen room view at ROOM_VW × ROOM_VH
M.sprites = {} -- item-icon sprites (sprite_key -> {img, scale})
M.floor_tiles = {} -- room_id  -> Image (16×16 NES floor tile)
M.tile_cache = {}
M.room_sprites = {} -- name     -> Image (furniture / rug sprites)

local TILE_PATH = "assets/kenney_tiny-dungeon/Tiles/"

-- Kenney tile sprites (sprite key -> tile filename, no extension)
local TILE_SPRITES = {
	glove = "tile_0116",
}

-- Direct PNG asset sprites (sprite key -> path)
local ASSET_SPRITES = {
	scroll = "assets/blank_scroll_01.png",
	book = "assets/bookicon.png",
	sword = "assets/kenney_tiny-dungeon/Tiles/tile_0104.png",
	laptop = "assets/laptop.png",
}

M.slack_bg = nil -- Slack popup background (assets/slack-bg.png), loaded in M.load
M.menu_bg = nil -- Title/play-menu background (assets/background.png), loaded in M.load
M.menu_glow_shader = nil -- neon monitor-glow shader over M.menu_bg, loaded in M.load
M.crt_shader = nil -- CRT power-on shader for the game intro, loaded in M.load
M.crt_overlay_shader = nil -- steady CRT-filter overlay (boot screen), loaded in M.load
M.crt_canvas = nil -- full-window canvas the game frame is captured into for CRT
M.intro_flash = nil -- transient white "flashbang" state for boot -> title handoff

-- Where the monitor screen sits in assets/background.png, as a UV-space
-- rect (xMin, yMin, xMax, yMax, each 0..1) of the source image. The glow
-- shader blooms deep indigo-purple light outward from this whole rect — the
-- entire screen is the light source, not a single point — so the dark room
-- reads as lit by the screen.
local MENU_GLOW_RECT = { 0.622, 0.060, 0.760, 0.220 }

-- Rosé Pine "overlay" (#26233a) — a dark, muted indigo-purple, used as the
-- glow tint instead of a bright neon color.
local MENU_GLOW_COLOR = { 0x26 / 255, 0x23 / 255, 0x3a / 255 }

-- Texture pixels per glow "block" — quantizing distance to this grid gives
-- the bloom a chunky, pixel-art stepped edge instead of a smooth analog glow.
local MENU_GLOW_PIXEL_SIZE = 18.0

local MENU_GLOW_SHADER_CODE = [[
	uniform vec4 glow_rect;
	uniform vec3 glow_color;
	uniform vec2 tex_size;
	uniform float time;

	vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
	{
		vec4 pixel = Texel(tex, uv);

		// snap uv to a coarse grid so the bloom reads as blocky/pixelated
		// rather than a smooth analog gradient
		vec2 grid = tex_size / ]] .. string.format("%.1f", MENU_GLOW_PIXEL_SIZE) .. [[;
		vec2 puv = floor(uv * grid) / grid;

		// aspect-correct distance (in source pixels) from the monitor screen
		// rect — zero anywhere inside it, so the whole screen glows evenly
		// and light falls off from its edges outward
		vec2 outside = max(glow_rect.xy - puv, puv - glow_rect.zw);
		outside = max(outside, vec2(0.0));
		float dist = length(outside * tex_size);

		// darken the room overall for a moodier, dark-room feel
		vec3 darkened = pixel.rgb * 0.55;

		// wide, soft indigo-purple gradient, quantized into a handful of
		// bands (pixelated, not smooth) so the light reads as ambient room
		// lighting spread across the whole frame rather than one glowing
		// blob — a slow, barely-there breathing pulse instead of a strobe
		float pulse = 0.95 + 0.05 * sin(time * 0.5);
		float glow = exp(-dist / 550.0) * pulse;
		glow = floor(glow * 10.0) / 10.0;
		vec3 neon = glow_color * glow;

		vec3 result = darkened + neon;

		// gentle vignette so the edges recede into darkness
		vec2 vc = uv - vec2(0.5);
		float vig = 1.0 - smoothstep(0.35, 0.9, length(vc));
		result *= mix(0.7, 1.0, vig);

		return vec4(result, pixel.a) * color;
	}
]]

-- CRT power-on shader for the game intro. Given a `progress` uniform (0..1) it
-- transforms the captured game frame into an old-monitor switch-on: the picture
-- collapses to a bright horizontal line, snaps open vertically, then the image
-- fills in with scanlines, a bright flash, and a settle to normal. Also applies
-- a light barrel curve + scanlines while active. Filled in during implementation.
local CRT_SHADER_CODE = [[
	uniform float progress;   // 0 = fully off, 1 = fully on
	uniform vec2 tex_size;    // canvas dimensions in px (for scanline frequency)

	vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
	{
		// Overall CRT-filter strength: full while switching on, faded to 0 once
		// the picture has settled — so the effect only "lives" during the intro.
		float crt = 1.0 - smoothstep(0.6, 1.0, progress);

		// Barrel/curvature distortion of the whole frame (stronger while on).
		vec2 cc = uv - 0.5;
		float r2 = dot(cc, cc);
		vec2 duv = cc * (1.0 + r2 * 0.18 * crt) + 0.5;
		vec2 c = duv - 0.5;

		// Vertical unfold. Ease-IN (pow > 1): crawls open near the center line,
		// then whips out to the top/bottom edges — the non-uniform CRT snap.
		// Opening finishes by progress ~0.6, leaving a settle/flash tail.
		float a = clamp(progress / 0.6, 0.0, 1.0);
		float openY = max(pow(a, 2.6), 0.0016);

		// The currently-lit vertical band (half-height). Outside it, dark bezel.
		float band = 0.5 * openY;
		if (abs(c.y) > band) {
			return vec4(0.0, 0.0, 0.0, 1.0);
		}

		// Un-squash: stretch the band back out so the picture springs open from
		// the center line.
		vec2 suv = vec2(c.x + 0.5, c.y / openY + 0.5);
		// Curvature can push samples past the frame — treat those as bezel.
		if (suv.x < 0.0 || suv.x > 1.0) {
			return vec4(0.0, 0.0, 0.0, 1.0);
		}

		// Chromatic aberration: split R/B horizontally (scaled by filter).
		float ca = 0.004 * crt;
		vec3 col;
		col.r = Texel(tex, vec2(clamp(suv.x + ca, 0.0, 1.0), suv.y)).r;
		col.g = Texel(tex, suv).g;
		col.b = Texel(tex, vec2(clamp(suv.x - ca, 0.0, 1.0), suv.y)).b;

		// Bright bloom while nearly-closed (the hot scan line), plus a short
		// over-bright flash as the screen finishes opening, then settles to 1.0.
		float lineGlow = 1.0 - openY;
		float flash = smoothstep(0.45, 0.6, progress) * (1.0 - smoothstep(0.6, 0.85, progress));
		col *= 1.0 + lineGlow * 2.5 + flash * 0.5;

		// Hot green-white core along the collapsing scan line, early on.
		float core = smoothstep(band, 0.0, abs(c.y)) * lineGlow;
		col += vec3(0.55, 1.0, 0.65) * core * 0.8;

		// Scanlines, present through the intro and fading as it completes.
		float scan = 0.8 + 0.2 * sin(duv.y * tex_size.y * 3.14159);
		col *= mix(1.0, scan, crt * 0.6);

		// Vignette so the tube edges recede into darkness (intro only).
		float vig = 1.0 - smoothstep(0.35, 0.85, length(cc));
		col *= mix(1.0, vig, crt * 0.5);

		return vec4(col, 1.0) * color;
	}
]]

-- Steady CRT-filter overlay (no unfold): subtle barrel curvature, scanlines,
-- chromatic aberration, flicker and vignette, applied at a fixed strength.
-- Used to give the boot screen an old-monitor look.
local CRT_OVERLAY_SHADER_CODE = [[
	uniform vec2 tex_size;
	uniform float time;

	vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
	{
		vec2 cc = uv - 0.5;
		float r2 = dot(cc, cc);
		vec2 duv = cc * (1.0 + r2 * 0.10) + 0.5;
		if (duv.x < 0.0 || duv.x > 1.0 || duv.y < 0.0 || duv.y > 1.0) {
			return vec4(0.0, 0.0, 0.0, 1.0);
		}

		// chromatic aberration
		float ca = 0.0016;
		vec3 col;
		col.r = Texel(tex, vec2(duv.x + ca, duv.y)).r;
		col.g = Texel(tex, duv).g;
		col.b = Texel(tex, vec2(duv.x - ca, duv.y)).b;

		// scanlines + faint flicker
		float scan = 0.85 + 0.15 * sin(duv.y * tex_size.y * 3.14159);
		col *= scan;
		col *= 0.97 + 0.03 * sin(time * 48.0);

		// vignette
		float vig = 1.0 - smoothstep(0.4, 0.95, length(cc));
		col *= mix(0.72, 1.0, vig);

		return vec4(col, 1.0) * color;
	}
]]

local SPRITE_TARGET_PX = 80 -- item icons are displayed at this size

local NES_SCALE = 3 -- each 16×16 floor tile rendered at 48×48 px

local FURNITURE_H = 230 -- px reserved below the banner for back-wall furniture

local function load_img(path, filter)
	local ok, img = pcall(love.graphics.newImage, path)
	if ok then
		img:setFilter(filter or "linear", filter or "linear")
	end
	return ok and img or nil
end

local function get_tile(path)
  if M.tile_cache[path] ~= nil then
    return M.tile_cache[path]
  end

  local img = load_img(path, "nearest")
  M.tile_cache[path] = img or false
  return M.tile_cache[path]
end


-- The default UI font is the shipped pixel (Minecraft-style) font, but a local
-- `font.ttf` (gitignored) overrides it if the user drops one in.
local function pixel_font_path()
	if love.filesystem.getInfo("font.ttf") then
		return "font.ttf"
	elseif love.filesystem.getInfo("monocraft.ttf") then
		return "monocraft.ttf"
	end
	return nil
end

-- The terminal panel font is the clean monospace (JetBrains Mono), matching the
-- boot and mode-select screens. Falls back to the pixel font, then LÖVE default.
local function load_terminal_font()
	local size = math.max(6, math.floor(16 * M.font_scale + 0.5))
	if love.filesystem.getInfo("font_mono.ttf") then
		M.font_term = love.graphics.newFont("font_mono.ttf", size)
	elseif pixel_font_path() then
		M.font_term = love.graphics.newFont(pixel_font_path(), size)
		M.font_term:setFilter("nearest", "nearest")
	else
		M.font_term = love.graphics.newFont(size)
	end
	-- The status bar holds one line of terminal-font text, so its height must
	-- track the (scaled) font or the text overflows at high zoom.
	M.STATUS_H = math.ceil(M.font_term:getHeight() + 2 * M.STATUS_PAD_V)
end

local function load_fixed_fonts()
	-- The pixel (Minecraft-style) font is now used ONLY in the room view: its
	-- name banner, item labels, and minimap cell labels.
	local path = pixel_font_path()
	if path then
		M.font_room = love.graphics.newFont(path, 16)
		M.font_room_big = love.graphics.newFont(path, 30)
		M.font_room_small = love.graphics.newFont(path, 12)
		for _, f in ipairs({ M.font_room, M.font_room_big, M.font_room_small }) do
			f:setFilter("nearest", "nearest")
		end
	else
		M.font_room = love.graphics.newFont(14)
		M.font_room_big = love.graphics.newFont(26)
		M.font_room_small = love.graphics.newFont(10)
	end
	-- Everything else in the UI (terminal, status bar, win screen, popups, title
	-- and menu screens) uses the clean monospace terminal font — the same one the
	-- boot and mode-select screens use.
	if love.filesystem.getInfo("font_mono.ttf") then
		M.font_mono = love.graphics.newFont("font_mono.ttf", 15)
		M.font_mono_big = love.graphics.newFont("font_mono.ttf", 22)
		M.font = love.graphics.newFont("font_mono.ttf", 16)
		M.font_big = love.graphics.newFont("font_mono.ttf", 30)
		M.font_small = love.graphics.newFont("font_mono.ttf", 12)
	else
		M.font = M.font_room
		M.font_big = M.font_room_big
		M.font_small = M.font_room_small
		M.font_mono = M.font
		M.font_mono_big = M.font_big
	end
	-- Handwritten evidence (scroll popups).
	if love.filesystem.getInfo("handwriting.ttf") then
		M.font_handwriting = love.graphics.newFont("handwriting.ttf", 16)
		M.font_handwriting_large = love.graphics.newFont("handwriting.ttf", 48)
	end
end

-- The editor pane's own text size, independent of the terminal's zoom. Nothing
-- about the layout depends on it (the pane wraps to whatever fits), so unlike
-- set_font_scale this needs no resize or rewrap. screens/game.lua resets it to
-- 1 when a run starts, so it lasts a session but not across a quit.
local function load_vim_font()
	local size = math.max(6, math.floor(16 * M.vim_font_scale + 0.5))
	if love.filesystem.getInfo("font_mono.ttf") then
		M.font_vim = love.graphics.newFont("font_mono.ttf", size)
	elseif pixel_font_path() then
		M.font_vim = love.graphics.newFont(pixel_font_path(), size)
		M.font_vim:setFilter("nearest", "nearest")
	else
		M.font_vim = love.graphics.newFont(size)
	end
end

function M.set_vim_font_scale(s)
	local clamped = math.max(0.6, math.min(2.5, s))
	if clamped == M.vim_font_scale and M.font_vim then
		return false
	end
	M.vim_font_scale = clamped
	load_vim_font()
	return true
end

function M.set_font_scale(s)
	local clamped = math.max(0.6, math.min(2.5, s))
	if clamped == M.font_scale then
		return false
	end
	M.font_scale = clamped
	load_terminal_font()
	-- STATUS_H just changed with the font, which shifts the room/terminal split;
	-- re-run the layout so the panels stay consistent (callers then rewrap).
	M.resize(M.W, M.H)
	return true
end

function M.load()
	load_fixed_fonts()
	load_terminal_font()
	load_vim_font()
	love.graphics.setFont(M.font)

	-- Item icon sprites (Kenney tiles + direct assets)
	for key, tile in pairs(TILE_SPRITES) do
		local img = load_img(TILE_PATH .. tile .. ".png", "nearest")
		if img then
			M.sprites[key] = { img = img, scale = SPRITE_TARGET_PX / img:getWidth() }
		end
	end
	for key, path in pairs(ASSET_SPRITES) do
		local img = load_img(path, "nearest")
		if img then
			M.sprites[key] = { img = img, scale = SPRITE_TARGET_PX / img:getWidth() }
		end
	end

	-- Floor tiles (16×16 NES PNGs). The Series C rooms reuse the manor floor
	-- art from the room each one replaces; new rooms fall back to solid color.
	local FLOOR_ASSET = {
		foyer = "foyer",
		home_office = "library",
		den = "study",
		sunroom = "conservatory",
		cellar = "cellar",
		garage = "bedroom",
	}
	for room_id, asset in pairs(FLOOR_ASSET) do
		local img = load_img("assets/sprites/floor/" .. asset .. ".png", "nearest")
		if img then
			M.floor_tiles[room_id] = img
		end
	end

	-- Slack popup background
	M.slack_bg = load_img("assets/slack-bg.png", "nearest")

	-- Title/play-menu background
	M.menu_bg = load_img("assets/background.png", "linear")
	local shader_ok, shader = pcall(love.graphics.newShader, MENU_GLOW_SHADER_CODE)
	M.menu_glow_shader = shader_ok and shader or nil

	-- CRT power-on shader + full-window capture canvas (sized in M.resize).
	local crt_ok, crt = pcall(love.graphics.newShader, CRT_SHADER_CODE)
	M.crt_shader = crt_ok and crt or nil
	local ov_ok, ov = pcall(love.graphics.newShader, CRT_OVERLAY_SHADER_CODE)
	M.crt_overlay_shader = ov_ok and ov or nil

	-- Furniture / rug sprites (2dpixx individual PNGs)
	for _, name in ipairs({
		"dresser_flower",
		"dresser",
		"shelf_full",
		"shelf_empty",
		"painting",
		"clock",
		"mirror",
		"armoire",
		"rug",
	}) do
		local img = load_img("assets/sprites/furniture/" .. name .. ".png", "linear")
		if img then
			M.room_sprites[name] = img
		end
	end

	M.room_canvas = love.graphics.newCanvas(ROOM_VW, ROOM_VH)
	M.room_canvas:setFilter("nearest", "nearest")

	local w, h = love.graphics.getDimensions()
	M.resize(w, h)
end

-- Draws M.menu_bg scaled to cover the cw×ch window (cropping overflow, never
-- letterboxing), then an optional darkening overlay on top. Used by the
-- title and play-menu screens.
function M.draw_menu_background(cw, ch, darken)
	if M.menu_bg then
		local iw, ih = M.menu_bg:getDimensions()
		local scale = math.max(cw / iw, ch / ih)
		local dw, dh = iw * scale, ih * scale
		love.graphics.setColor(1, 1, 1, 1)
		if M.menu_glow_shader then
			M.menu_glow_shader:send("glow_rect", MENU_GLOW_RECT)
			M.menu_glow_shader:send("glow_color", MENU_GLOW_COLOR)
			M.menu_glow_shader:send("tex_size", { iw, ih })
			M.menu_glow_shader:send("time", love.timer.getTime())
			love.graphics.setShader(M.menu_glow_shader)
		end
		love.graphics.draw(M.menu_bg, (cw - dw) / 2, (ch - dh) / 2, 0, scale, scale)
		love.graphics.setShader()
	end
	if darken then
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", 0, 0, cw, ch)
	end
end

-- Render `draw_fn` (which draws a full game frame) through the CRT power-on
-- effect at the given `progress` (0..1): capture the frame into M.crt_canvas,
-- then blit it back to the screen through M.crt_shader so the game appears to
-- switch on like an old monitor.
function M.draw_crt_power_on(progress, draw_fn)
	if not M.crt_shader then
		draw_fn()
		return
	end

	local w, h = love.graphics.getDimensions()
	if not M.crt_canvas or M.crt_canvas:getWidth() ~= w or M.crt_canvas:getHeight() ~= h then
		M.crt_canvas = love.graphics.newCanvas(w, h)
	end

	-- Capture the frame into our canvas (draw_fn restores to this target since
	-- M.draw now restores the previous canvas rather than forcing the screen).
	local prev_canvas = love.graphics.getCanvas()
	love.graphics.setCanvas(M.crt_canvas)
	love.graphics.clear(0, 0, 0, 1)
	draw_fn()
	love.graphics.setCanvas(prev_canvas)

	-- Blit the captured frame back through the CRT shader.
	love.graphics.setColor(1, 1, 1, 1)
	M.crt_shader:send("progress", progress)
	M.crt_shader:send("tex_size", { w, h })
	love.graphics.setShader(M.crt_shader)
	love.graphics.draw(M.crt_canvas, 0, 0)
	love.graphics.setShader()
end

-- Render `draw_fn` through the steady CRT-filter overlay (scanlines/curvature/
-- vignette). Same capture-and-blit approach as the power-on, but with a fixed
-- filter instead of the unfold. Used by the boot screen.
function M.draw_crt_overlay(draw_fn)
	if not M.crt_overlay_shader then
		draw_fn()
		return
	end

	local w, h = love.graphics.getDimensions()
	if not M.crt_canvas or M.crt_canvas:getWidth() ~= w or M.crt_canvas:getHeight() ~= h then
		M.crt_canvas = love.graphics.newCanvas(w, h)
	end

	local prev_canvas = love.graphics.getCanvas()
	love.graphics.setCanvas(M.crt_canvas)
	love.graphics.clear(0, 0, 0, 1)
	draw_fn()
	love.graphics.setCanvas(prev_canvas)

	love.graphics.setColor(1, 1, 1, 1)
	M.crt_overlay_shader:send("tex_size", { w, h })
	M.crt_overlay_shader:send("time", love.timer.getTime())
	love.graphics.setShader(M.crt_overlay_shader)
	love.graphics.draw(M.crt_canvas, 0, 0)
	love.graphics.setShader()
end

-- ---- "flashbang" handoff (boot screen -> title screen) ----
-- A quick white flash whose "in" half plays over the boot screen and whose
-- "out" half fades away over the title screen, hiding the cut between them.

function M.flash_begin()
	M.intro_flash = { t = 0, phase = "in", dur_in = 0.12, dur_out = 0.5 }
end

-- Advance the flash. Returns "switch" the moment the white-out peaks (the caller
-- should change screens then), "done" when the fade-out finishes, else nil.
function M.flash_update(dt)
	local f = M.intro_flash
	if not f then
		return nil
	end
	f.t = f.t + dt
	if f.phase == "in" then
		if f.t >= f.dur_in then
			f.phase = "out"
			f.t = 0
			return "switch"
		end
	elseif f.t >= f.dur_out then
		M.intro_flash = nil
		return "done"
	end
	return nil
end

function M.flash_active()
	return M.intro_flash ~= nil
end

-- Draw the white flash overlay at its current alpha (call last, on top).
function M.draw_intro_flash()
	local f = M.intro_flash
	if not f then
		return
	end
	local a
	if f.phase == "in" then
		a = math.min(1, f.t / f.dur_in)
	else
		a = 1 - math.min(1, f.t / f.dur_out)
	end
	if a <= 0 then
		return
	end
	local w, h = love.graphics.getDimensions()
	love.graphics.setColor(1, 1, 1, a)
	love.graphics.rectangle("fill", 0, 0, w, h)
	love.graphics.setColor(1, 1, 1, 1)
end

-- ---- shared title banner ----
-- The "TERMINAL MYSTERY" ASCII banner is drawn at one canonical position by both
-- the boot screen and the title screen, so the flashbang hand-off keeps it fixed.

local BANNER_OUTLINE = { 0x39 / 255, 0x35 / 255, 0x52 / 255 }
local BANNER_MAX_H_FRAC = 0.42 -- banner is capped to this fraction of window height

-- Compute the banner's layout for a cw×ch window: its scale (fit to both width
-- and height so it never clips, even at the min resolution), block metrics, and
-- position. Returned `bottom` is where content below (buttons/console) starts.
function M.title_banner_layout(cw, ch)
	local font = M.font_mono_big or M.font_big or M.font
	local lines = Banner.lines
	local maxw = 0
	for _, l in ipairs(lines) do
		maxw = math.max(maxw, font:getWidth(l))
	end
	local base_line_h = font:getHeight() * 1.08
	local base_block_h = #lines * base_line_h
	local scale = math.min(1.0, (cw - 80) / math.max(1, maxw), (ch * BANNER_MAX_H_FRAC) / base_block_h)
	local block_h = base_block_h * scale
	local cx = cw / 2
	local cy = ch * 0.33 -- proportional so it stays on-screen at any height
	local top = cy - block_h / 2
	return {
		font = font,
		scale = scale,
		line_h = base_line_h * scale,
		block_w = maxw * scale,
		block_h = block_h,
		cx = cx,
		top = top,
		bottom = top + block_h,
	}
end

-- Draw the banner for a cw×ch window in `fill` with a dark outline (the
-- LazyVim-style outlined block look). `count` limits how many lines are revealed
-- (nil = all); hidden lines still reserve their space so revealed lines stay at
-- their final position. Returns the block's bottom y.
function M.draw_title_banner(cw, ch, fill, count)
	local L = M.title_banner_layout(cw, ch)
	local prev = love.graphics.getFont()
	love.graphics.setFont(L.font)
	local lines = Banner.lines
	count = count or #lines
	local left = L.cx - L.block_w / 2
	local o = L.scale
	local y = L.top
	for i = 1, math.min(count, #lines) do
		local l = lines[i]
		if l ~= "" then
			love.graphics.setColor(BANNER_OUTLINE)
			for _, d in ipairs({ { -o, 0 }, { o, 0 }, { 0, -o }, { 0, o }, { -o, -o }, { o, -o }, { -o, o }, { o, o } }) do
				love.graphics.print(l, left + d[1], y + d[2], 0, L.scale, L.scale)
			end
			love.graphics.setColor(fill)
			love.graphics.print(l, left, y, 0, L.scale, L.scale)
		end
		y = y + L.line_h
	end
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(prev)
	return L.bottom
end

function M.terminal_text_width()
	return M.TERM_W - 2 * M.PAD
end

-- Word-wrap a chunk of text to fit the terminal panel. Manual newlines
-- inside a prose paragraph are treated as soft wraps and collapsed into
-- spaces so wide windows reflow the text to fill the available width.
-- Intentional breaks are preserved: blank lines (paragraph breaks), short
-- lines (list items like `ls` output), indented next lines, and lines
-- already ending in a non-word char like `.` `?` `/` `:` `]`.
--
-- Only prose reflows. A line is disqualified when it holds no space at all
-- (a bare path or filename, as `find` and `ls` emit) or when it holds a run
-- of two or more spaces (column-aligned records: Slack timestamps, access
-- logs, the guest list). Both sides of a join must look like prose, so a
-- long path can never swallow the entry after it.
function M.wrap_text(text)
	local font = M.font_term
	local maxw = M.terminal_text_width()
	local SOFT_THRESHOLD = 30

	local raw_lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(raw_lines, line)
	end

	-- Does this line read as prose, i.e. may it take part in a soft join?
	local function is_prose(line)
		local body = line:gsub("^%s+", "") -- leading indent is not a column gap
		if not body:find(" ", 1, true) then
			return false
		end
		return body:find("  ", 1, true) == nil
	end

	local function is_soft(prev, next_line)
		if #prev < SOFT_THRESHOLD then
			return false
		end
		if next_line == "" or next_line:match("^%s") then
			return false
		end
		if not is_prose(prev) or not is_prose(next_line) then
			return false
		end
		return prev:sub(-1):match("%w") ~= nil
	end

	local merged = {}
	local i = 1
	while i <= #raw_lines do
		local joined = raw_lines[i]
		local j = i + 1
		while j <= #raw_lines and is_soft(raw_lines[j - 1], raw_lines[j]) do
			joined = joined .. " " .. raw_lines[j]
			j = j + 1
		end
		table.insert(merged, joined)
		i = j
	end

	local result = {}
	for _, raw in ipairs(merged) do
		if raw == "" then
			table.insert(result, "")
		elseif font:getWidth(raw) <= maxw then
			table.insert(result, raw)
		else
			local indent = raw:match("^(%s*)") or ""
			local rest = raw:sub(#indent + 1)
			local current = indent
			for word in rest:gmatch("%S+") do
				local sep = (current == indent) and "" or " "
				local trial = current .. sep .. word
				if font:getWidth(trial) > maxw and current ~= indent then
					table.insert(result, current)
					current = indent .. word
				else
					current = trial
				end
			end
			if current ~= indent or #result == 0 then
				table.insert(result, current)
			end
		end
	end
	return result
end

-- ---------- panels ----------

-- `frozen` (the notes editor has focus): the prompt still shows whatever was
-- half-typed, but the blinking block cursor is hidden — only one pane owns the
-- keyboard at a time, and the editor draws its own.
local function draw_terminal(state, term, frozen)
	love.graphics.setColor(C.term_bg)
	love.graphics.rectangle("fill", 0, 0, M.TERM_W, M.H - M.STATUS_H)

	love.graphics.setFont(M.font_term)
	local line_h = M.font_term:getHeight() * 1.25

	-- reserve one line at the bottom for the prompt
	local prompt_y = M.H - M.STATUS_H - M.PAD - line_h
	local body_top = M.PAD
	local body_bottom = prompt_y - M.PAD
	local visible_lines = math.max(1, math.floor((body_bottom - body_top) / line_h))

	local total = #term.lines
	local end_idx = total - term.scroll
	if end_idx < 0 then
		end_idx = 0
	end
	local start_idx = math.max(1, end_idx - visible_lines + 1)

	local y = body_top
	for i = start_idx, end_idx do
		local entry = term.lines[i]
		if entry then
			love.graphics.setColor(LINE_COLOURS[entry.kind] or C.term_text)
			love.graphics.print(entry.text, M.PAD, y)
		end
		y = y + line_h
	end

	-- prompt
	love.graphics.setColor(C.prompt)
	local prompt = "> "
	love.graphics.print(prompt, M.PAD, prompt_y)
	love.graphics.setColor(C.term_user)
	local px = M.PAD + M.font_term:getWidth(prompt)
	love.graphics.print(term.input, px, prompt_y)
	if term.cursor_visible and not frozen then
		-- Block cursor at term.cursor_pos (a byte offset). When it sits over a
		-- character, redraw that glyph in the background colour so it stays legible.
		local pos = term.cursor_pos or #term.input
		local cx = px + M.font_term:getWidth(term.input:sub(1, pos))
		local after = term.input:sub(pos + 1)
		local nextchar = ""
		if after ~= "" then
			nextchar = after:sub(1, (utf8.offset(after, 2) or (#after + 1)) - 1)
		end
		local cw = (nextchar ~= "") and M.font_term:getWidth(nextchar) or M.font_term:getWidth("M")
		love.graphics.setColor(C.term_user)
		love.graphics.rectangle("fill", cx, prompt_y, cw, M.font_term:getHeight())
		if nextchar ~= "" then
			love.graphics.setColor(C.term_bg)
			love.graphics.print(nextchar, cx, prompt_y)
		end
	end

	if term.scroll > 0 then
		love.graphics.setColor(C.term_dim)
		love.graphics.print("[ scrolled — PgDn to return ]", M.PAD, prompt_y - line_h)
	end
end

-- Tree layout: computed once from the room graph, cached for the session.
-- Leaves get consecutive integer x values; parents are averaged over children.
-- y = 1-based depth from root. Guarantees minimum x-spacing of 1 between
-- any two nodes at the same depth, so cells never overlap with room_pad > 0.
local layout_cache, layout_grid_w, layout_grid_h

local function build_layout()
	if layout_cache then
		return
	end

	-- Hidden rooms are never drawn on the map, so exclude them from the tree
	-- entirely — otherwise a hidden child (e.g. .closet under the Den) adds an
	-- extra depth row that renders as blank space under the visible cells.
	local children = {}
	local root_id
	for id, r in pairs(World.rooms) do
		if not r.hidden then
			children[id] = {}
			if not r.parent then
				root_id = id
			end
		end
	end
	for id, r in pairs(World.rooms) do
		if not r.hidden and r.parent and children[r.parent] then
			table.insert(children[r.parent], id)
		end
	end
	for _, list in pairs(children) do
		table.sort(list)
	end

	local positions = {}
	local leaf_count = 0
	local max_depth = 0

	local function layout(id, depth)
		if depth > max_depth then
			max_depth = depth
		end
		local kids = children[id]
		if #kids == 0 then
			leaf_count = leaf_count + 1
			positions[id] = { x = leaf_count, y = depth }
		else
			local x_sum = 0
			for _, kid in ipairs(kids) do
				layout(kid, depth + 1)
				x_sum = x_sum + positions[kid].x
			end
			positions[id] = { x = x_sum / #kids, y = depth }
		end
	end

	layout(root_id, 1)
	layout_cache = positions
	layout_grid_w = leaf_count
	layout_grid_h = max_depth
end

-- Compute the screen rect of one minimap room cell given the minimap origin.
local function minimap_room_rect(pos, mx, my, cell_w, cell_h, room_pad)
	local cx = mx + (pos.x - 1) * cell_w
	local cy = my + (pos.y - 1) * cell_h
	return cx + room_pad, cy + room_pad, cell_w - 2 * room_pad, cell_h - 2 * room_pad
end

-- Draw the minimap into the rectangle (mx, my, mw, mh).
local function draw_minimap(state, mx, my, mw, mh)
	build_layout()

	local cell_w = mw / layout_grid_w
	local cell_h = mh / layout_grid_h
	local room_pad = 4

	-- background
	love.graphics.setColor(C.map_bg)
	love.graphics.rectangle("fill", mx, my, mw, mh, 4, 4)
	love.graphics.setColor(C.map_border)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", mx, my, mw, mh, 4, 4)

	-- connections (skip any edge that touches a hidden room)
	love.graphics.setColor(C.connection)
	love.graphics.setLineWidth(1)
	local drawn = {}
	for id, room in pairs(World.rooms) do
		if not room.hidden then
			for _, exit_id in ipairs(World.get_exits(id)) do
				if not World.rooms[exit_id].hidden then
					local key = (id < exit_id) and (id .. "|" .. exit_id) or (exit_id .. "|" .. id)
					if not drawn[key] then
						drawn[key] = true
						local x1, y1, w1, h1 = minimap_room_rect(layout_cache[id], mx, my, cell_w, cell_h, room_pad)
						local x2, y2, w2, h2 =
							minimap_room_rect(layout_cache[exit_id], mx, my, cell_w, cell_h, room_pad)
						love.graphics.line(x1 + w1 / 2, y1 + h1 / 2, x2 + w2 / 2, y2 + h2 / 2)
					end
				end
			end
		end
	end

	-- room cells (skip hidden rooms)
	for id, room in pairs(World.rooms) do
		if not room.hidden then
			local x, y, w, h = minimap_room_rect(layout_cache[id], mx, my, cell_w, cell_h, room_pad)
			local is_current = (state.current_room == id)
			local is_visited = state.visited[id] == true

			local fill, text_color
			if is_current then
				fill, text_color = C.room_current, C.room_text_curr
			elseif is_visited then
				fill, text_color = C.room_visited, C.room_text
			else
				fill, text_color = C.room_unvisited, C.room_text_dim
			end

			love.graphics.setColor(fill)
			love.graphics.rectangle("fill", x, y, w, h, 3, 3)
			love.graphics.setColor(C.map_border)
			love.graphics.setLineWidth(1)
			love.graphics.rectangle("line", x, y, w, h, 3, 3)

			love.graphics.setFont(M.font_room_small)
			love.graphics.setColor(text_color)
			-- A short 3-letter code (a leading "The" is dropped first), e.g.
			-- "The Den" -> DEN, "Server Room" -> SER. `room.code` overrides.
			-- Scaled down to fit narrow cells so it never truncates.
			local base = room.name:gsub("^[Tt]he%s+", "")
			local label = room.code or base:gsub("[^%w]", ""):upper():sub(1, 3)
			local lw = M.font_room_small:getWidth(label)
			local ls = math.min(1, (w - 4) / math.max(1, lw))
			love.graphics.print(label, x + (w - lw * ls) / 2,
				y + (h - M.font_room_small:getHeight() * ls) / 2, 0, ls, ls)
		end
	end
end

local function draw_grid_tiles(tiles, gx, gy, gw, gh)
  if not tiles.legend or not tiles.layers or not tiles.layers[1]
      or not tiles.layers[1][1] or #tiles.layers[1][1] == 0 then
    return
  end

    local cols = #tiles.layers[1][1]
    local rows = #tiles.layers[1]
    local cell = math.min(gw/cols, gh/rows)
    for _, layer in ipairs(tiles.layers) do
      if #layer ~= rows then return end
      for row = 1, rows do
        if type(layer[row]) ~= "string" or #layer[row] ~= cols then return end
        for col =1, cols do
          local e = tiles.legend[layer[row]:sub(col, col)]
          local path
          local w = 1
          local h = 1
          local tint
          if type(e) == "table" then
            w = e.w or 1
            h = e.h or 1
            path = e.path
            tint = e.tint
          else
            path = e
          end
          if path then
            local img = get_tile(path)
            if img then
              if tint then
                love.graphics.setColor(tint)
              else
                love.graphics.setColor(1, 1, 1)
              end
              local px = gx + (col-1) * cell
              local py = gy + (row-1) * cell
              if w < 0 then
                px = gx + (col -1 + math.abs(w)) * cell
              end
              if h < 0 then
                py = gy + (row -1 + math.abs(h)) * cell
              end
              love.graphics.draw(img, px, py , 0, (w*cell) / img:getWidth(), (h*cell) / img:getHeight())
            end
          end
        end
      end
    end
end

-- Draw the main 2D top-down room view. Renders into the room canvas at the
-- fixed virtual resolution; coords are canvas-local (0..ROOM_VW, 0..ROOM_VH).
local function draw_room_view(state)
	local px = 0
	local py = 0
	local pw = ROOM_VW
	local ph = ROOM_VH
	local room_id = state.current_room
	local room_def = World.rooms[room_id]
	local wall = room_def.wall or { 0.18, 0.16, 0.20 }
	local floor = room_def.floor or { 0.30, 0.28, 0.26 }

	-- ---- outer wall fill ----
	love.graphics.setColor(wall)
	love.graphics.rectangle("fill", px, py, pw, ph)

	-- ---- floor interior (inset 24 px) ----
	local BORDER = 24
	local fx = px + BORDER
	local fy = py + BORDER
	local fw = pw - 2 * BORDER
	local fh = ph - 2 * BORDER
  if room_def.tiles then
    draw_grid_tiles(room_def.tiles, px, py, pw, ph)
  else
    -- ---- tiled NES floor ----
    local tile_px = 16 * NES_SCALE -- 48 px rendered tile
    local floor_img = M.floor_tiles[room_id]
    love.graphics.setScissor(fx, fy, fw, fh)
    if floor_img then
      love.graphics.setColor(1, 1, 1)
      local ry = fy
      while ry < fy + fh do
        local rx = fx
        while rx < fx + fw do
          love.graphics.draw(floor_img, rx, ry, 0, NES_SCALE, NES_SCALE)
          rx = rx + tile_px
        end
        ry = ry + tile_px
      end
      local t = room_def.floor_tint or { 0, 0, 0, 0 }
      love.graphics.setColor(t[1], t[2], t[3], t[4])
      love.graphics.rectangle("fill", fx, fy, fw, fh)
    else
      love.graphics.setColor(floor)
      love.graphics.rectangle("fill", fx, fy, fw, fh)
    end
    love.graphics.setScissor()

    -- ---- rug ----
    if room_def.rug then
      local rug = M.room_sprites.rug
      if rug then
        local rw = fw * 0.54
        local rs = rw / rug:getWidth()
        local rh = rug:getHeight() * rs
        love.graphics.setColor(1, 1, 1, 0.82)
        love.graphics.draw(rug, fx + (fw - rw) / 2, fy + fh - rh - 10, 0, rs, rs)
      end
    end

  end
    -- ---- back-wall furniture ----
    local BANNER_H = M.font_room_big:getHeight() + M.PAD
    local fur_y = fy + BANNER_H + 6
    local furn = room_def.furniture
    if furn then
      love.graphics.setScissor(fx, fy, fw, fh)
      for _, piece in ipairs(furn) do
        local name, nx, max_h = piece[1], piece[2], piece[3]
        local img = M.room_sprites[name]
        if img then
          local sc = max_h / img:getHeight()
          local sw = img:getWidth() * sc
          local dx = math.max(fx, math.min(fx + nx * fw - sw / 2, fx + fw - sw))
          love.graphics.setColor(1, 1, 1)
          love.graphics.draw(img, dx, fur_y, 0, sc, sc)
        end
      end
      love.graphics.setScissor()
    end
	-- Inner shadow along the inset-floor's top and left edges. Only for rooms
	-- that use the inset floor; tile rooms fill the whole canvas, so the shadow
	-- would just float over the tiles as a phantom border.
	if not room_def.tiles then
		love.graphics.setColor(0, 0, 0, 0.22)
		love.graphics.setLineWidth(4)
		love.graphics.line(fx, fy, fx + fw, fy)
		love.graphics.line(fx, fy, fx, fy + fh)
	end

	-- ---- room name banner (full width, pinned to the top edge) ----
	love.graphics.setColor(0, 0, 0, 0.52)
	love.graphics.rectangle("fill", px, py, pw, BANNER_H)
	love.graphics.setColor(wall[1] + 0.15, wall[2] + 0.15, wall[3] + 0.15, 0.6)
	love.graphics.setLineWidth(1)
	love.graphics.line(px + 8, py + BANNER_H, px + pw - 8, py + BANNER_H)

	love.graphics.setFont(M.font_room_big)
	love.graphics.setColor(C.status_text)
	local rname = room_def.name
	local rnw = M.font_room_big:getWidth(rname)
	love.graphics.print(rname, px + (pw - rnw) / 2, py + (BANNER_H - M.font_room_big:getHeight()) / 2)

	-- ---- items ----
	local ITEM_PX = SPRITE_TARGET_PX
	local GLOW_R = 34

	local ITEM_TOP = fy + BANNER_H + FURNITURE_H + M.PAD
	local ITEM_BOTTOM = fy + fh - 160
	local ITEM_LEFT = fx + M.PAD
	local ITEM_RIGHT = fx + fw - M.PAD
	local item_zone_w = ITEM_RIGHT - ITEM_LEFT
	local item_zone_h = math.max(1, ITEM_BOTTOM - ITEM_TOP)

	love.graphics.setFont(M.font_room)
	local items = World.get_items_in_room(room_id)
	for _, item in ipairs(items) do
		local cx = ITEM_LEFT + item.x * item_zone_w
		local cy = ITEM_TOP + item.y * item_zone_h
		local ix = cx - ITEM_PX / 2
		local iy = cy - ITEM_PX / 2

		love.graphics.setColor(0.95, 0.78, 0.25, 0.18)
		love.graphics.circle("fill", cx, cy, GLOW_R + 16)
		love.graphics.setColor(0.95, 0.78, 0.25, 0.42)
		love.graphics.circle("fill", cx, cy, GLOW_R)

		local spr = M.sprites[item.sprite]
		if spr then
			love.graphics.setColor(1, 1, 1)
			love.graphics.draw(spr.img, ix, iy, 0, spr.scale, spr.scale)
		else
			love.graphics.setColor(C.item_box)
			love.graphics.rectangle("fill", ix, iy, ITEM_PX, ITEM_PX, 6, 6)
			love.graphics.setColor(C.item_box_border)
			love.graphics.setLineWidth(2)
			love.graphics.rectangle("line", ix, iy, ITEM_PX, ITEM_PX, 6, 6)
		end

		local label = item.filename:gsub("%.%w+$", "")
		local lw = M.font_room:getWidth(label)
		local lx = cx - lw / 2
		local ly = iy + ITEM_PX + 4
		love.graphics.setColor(0, 0, 0, 0.65)
		love.graphics.print(label, lx + 1, ly + 1)
		love.graphics.setColor(C.item_label)
		love.graphics.print(label, lx, ly)
	end

	-- ---- minimap overlay (bottom-right, inset 8 px) ----
	-- Toggled with Ctrl/Cmd+M. Wide enough that a 3-letter code fits a cell at
	-- 1:1 (no muddy pixel-font scaling); only 2 rows tall now that hidden rooms
	-- are excluded, so there's no blank strip under the cells.
	if not state.minimap_hidden then
		local MM_W = 224
		local MM_H = 92
		local MM_INS = 8
		local mm_x = px + pw - MM_W - MM_INS
		local mm_y = py + ph - MM_H - MM_INS
		draw_minimap(state, mm_x, mm_y, MM_W, MM_H)
	end
end

local function format_time(t)
	local m = math.floor(t / 60)
	local s = t - m * 60
	return string.format("%02d:%05.2f", m, s)
end

local function draw_status_bar(state)
	love.graphics.setColor(C.status_bg)
	love.graphics.rectangle("fill", 0, M.H - M.STATUS_H, M.W, M.STATUS_H)

	love.graphics.setFont(M.font_term)
	love.graphics.setColor(C.status_text)
	local y = M.H - M.STATUS_H + (M.STATUS_H - M.font_term:getHeight()) / 2
	local GAP = 24
	local avail = M.W - 2 * M.PAD

	-- Left cluster: full labels normally, abbreviated when they'd overflow the
	-- bar ("time:"->"t:", "commands:"->"c:", and the seconds' fraction dropped).
	local n = tostring(state.command_count)
	local t_full = format_time(state.elapsed)
	local left = "time: " .. t_full .. "   commands: " .. n
	if M.font_term:getWidth(left) > avail then
		local t_short = t_full:gsub("%..*$", "") -- drop centiseconds
		left = "t: " .. t_short .. "  c: " .. n
	end
	love.graphics.print(left, M.PAD, y)

	-- Right hint, degraded then dropped entirely once it no longer fits in the
	-- space left over beside the (possibly abbreviated) left cluster.
	local remaining = avail - M.font_term:getWidth(left) - GAP
	local hints = {
		"PgUp/PgDn scroll | Up/Dn history | type `help`",
		"PgUp/PgDn scroll | type `help`",
		"type `help`",
	}
	for _, hint in ipairs(hints) do
		local hw = M.font_term:getWidth(hint)
		if hw <= remaining then
			love.graphics.print(hint, M.W - M.PAD - hw, y)
			break
		end
	end
end

local VIM_DIVIDER_W = 2 -- rule drawn down the terminal/editor seam

-- The notes editor pane (see vim.lua), drawn into M.vim_x/y/w/h. Line numbers
-- in a gutter, buffer rows hard-wrapped at the pane width (no horizontal
-- scroll, continuation rows get a blank gutter), block cursor, and a status
-- line along the bottom showing the mode / vim.msg / the `:` command line.
-- Owns vim.scroll: it keeps the cursor row visible.
--
-- The terminal font is monospaced, so every column is char_w wide and the
-- cursor's screen position is pure arithmetic — no per-substring measuring.
local function draw_vim_view(vim)
	local x, y, w, h = M.vim_x, M.vim_y, M.vim_w, M.vim_h
	local font = M.font_vim or M.font_term
	local line_h = font:getHeight() * 1.25
	local char_w = font:getWidth("M")

	love.graphics.setColor(C.term_bg)
	love.graphics.rectangle("fill", x, y, w, h)
	-- Rule down the seam so the split reads as two panes rather than one wide
	-- terminal. In terminal-only mode this is the only thing separating them.
	love.graphics.setColor(C.map_border)
	love.graphics.rectangle("fill", x, y, VIM_DIVIDER_W, h)
	love.graphics.setFont(font)

	local gutter = char_w * 4 -- "999 "
	local text_x = x + M.PAD + gutter
	local cols = math.max(1, math.floor((w - 2 * M.PAD - gutter) / char_w))
	local top = y + M.PAD
	local status_y = y + h - M.PAD - line_h
	local rows = math.max(1, math.floor((status_y - top) / line_h))

	-- Flatten the buffer into display rows. A buffer line always occupies
	-- floor(#line / cols) + 1 rows, so a line that exactly fills the width gets
	-- a trailing empty row — that's where the cursor sits when it's at the end
	-- of such a line. Only the first row of a line carries its number.
	local display = {}
	local first_row = {}
	for i, line in ipairs(vim.lines) do
		first_row[i] = #display + 1
		for c = 0, math.floor(#line / cols) do
			table.insert(display, {
				text = line:sub(c * cols + 1, (c + 1) * cols),
				num = (c == 0) and i or nil,
			})
		end
	end

	-- Scroll follows the cursor's display row.
	local cursor_row = first_row[vim.line] + math.floor(vim.col / cols)
	if cursor_row <= vim.scroll then
		vim.scroll = cursor_row - 1
	elseif cursor_row > vim.scroll + rows then
		vim.scroll = cursor_row - rows
	end
	vim.scroll = math.max(0, math.min(vim.scroll, math.max(0, #display - 1)))

	local row_y = top
	for r = vim.scroll + 1, vim.scroll + rows do
		local row = display[r]
		if row then
			if row.num then
				love.graphics.setColor(C.term_dim)
				love.graphics.print(string.format("%3d", row.num), x + M.PAD, row_y)
			end
			love.graphics.setColor(C.term_text)
			love.graphics.print(row.text, text_x, row_y)
			if r == cursor_row then
				-- Block cursor; the glyph under it is redrawn in the background
				-- colour so it stays legible.
				local ccol = vim.col % cols
				local cx = text_x + ccol * char_w
				local glyph = row.text:sub(ccol + 1, ccol + 1)
				love.graphics.setColor(C.term_user)
				love.graphics.rectangle("fill", cx, row_y, char_w, font:getHeight())
				if glyph ~= "" then
					love.graphics.setColor(C.term_bg)
					love.graphics.print(glyph, cx, row_y)
				end
			end
		else
			-- past the end of the buffer
			love.graphics.setColor(C.term_dim)
			love.graphics.print("~", x + M.PAD, row_y)
		end
		row_y = row_y + line_h
	end

	-- Status line: the `:` prompt while a command is being typed, otherwise the
	-- last message, otherwise the mode + cursor position.
	if vim.mode == "command" then
		love.graphics.setColor(C.term_user)
		local prompt = ":" .. vim.cmd
		love.graphics.print(prompt, x + M.PAD, status_y)
		love.graphics.rectangle("fill", x + M.PAD + #prompt * char_w, status_y, char_w, font:getHeight())
	else
		local status
		if vim.msg ~= "" then
			status = vim.msg
		elseif vim.mode == "insert" then
			status = "-- INSERT --"
		else
			status = string.format('"%s"%s  %d,%d', Vim.NAME, vim.dirty and " [+]" or "", vim.line, vim.col + 1)
		end
		love.graphics.setColor(C.system)
		love.graphics.print(status, x + M.PAD, status_y)
	end
end

local function draw_win_screen(state, best)
	love.graphics.setColor(C.win_overlay)
	love.graphics.rectangle("fill", 0, 0, M.W, M.H)

	local lines = {}
	table.insert(lines, { f = M.font_big, c = C.win_title, t = "CASE CLOSED" })
	table.insert(lines, { f = M.font, c = C.win_text, t = "" })
	table.insert(lines, { f = M.font, c = C.win_text, t = "You named the murderer: " .. World.murderer .. "." })
	table.insert(lines, { f = M.font, c = C.win_text, t = "" })

	table.insert(lines, { f = M.font_big, c = C.win_text, t = "this run" })
	table.insert(lines, {
		f = M.font,
		c = C.win_text,
		t = "time:     " .. format_time(state.win_time) .. (state.new_time_record and "    NEW RECORD" or ""),
	})
	table.insert(lines, {
		f = M.font,
		c = C.win_text,
		t = "commands: " .. tostring(state.win_commands) .. (state.new_cmds_record and "    NEW RECORD" or ""),
	})
	table.insert(lines, { f = M.font, c = C.win_text, t = "" })

	if best then
		table.insert(lines, { f = M.font_big, c = C.win_text, t = "personal best" })
		table.insert(lines, {
			f = M.font,
			c = C.win_text,
			t = "fastest:        " .. format_time(best.best_time),
		})
		table.insert(lines, {
			f = M.font,
			c = C.win_text,
			t = "fewest commands: " .. tostring(best.best_commands),
		})
	end

	table.insert(lines, { f = M.font, c = C.win_text, t = "" })
	table.insert(lines, { f = M.font, c = C.term_dim, t = "press R to play again,  Esc for title" })

	-- compute total height for vertical centering
	local total_h = 0
	for _, ln in ipairs(lines) do
		total_h = total_h + ln.f:getHeight() * 1.35
	end
	local y = (M.H - total_h) / 2
	for _, ln in ipairs(lines) do
		love.graphics.setFont(ln.f)
		local color = ln.c
		if ln.t:find("NEW RECORD", 1, true) then
			color = C.win_record
		end
		love.graphics.setColor(color)
		local lw = ln.f:getWidth(ln.t)
		love.graphics.print(ln.t, (M.W - lw) / 2, y)
		y = y + ln.f:getHeight() * 1.35
	end
end

local POPUP_NAV_H = 26 -- reserved strip at the bottom of a paginated popup body

-- Draw a compact vertical pager  [ up-triangle ]  page / total  [ down-triangle ]
-- centered on (x, y, w). Up = previous page, down = next page. Triangles are
-- drawn as polygons so they render regardless of font glyph coverage. Publishes
-- the up/down hit rects for the input layer. `color` is a {r,g,b} table.
local function draw_page_nav(x, y, w, page, total, color)
	love.graphics.setFont(M.font)
	local lh = M.font:getHeight()
	local cy = y + POPUP_NAV_H / 2
	local tri = 6
	local gap = 16
	local label = page .. " / " .. total
	local lw = M.font:getWidth(label)
	local r, g, b = color[1], color[2], color[3]

	local total_w = tri * 2 + gap + lw + gap + tri * 2
	local sx = x + (w - total_w) / 2
	local up_cx = sx + tri
	local dn_cx = up_cx + tri + gap + lw + gap + tri

	love.graphics.setColor(r, g, b, page > 1 and 1 or 0.30)
	love.graphics.polygon("fill", up_cx, cy - tri, up_cx - tri, cy + tri, up_cx + tri, cy + tri)
	love.graphics.setColor(r, g, b)
	love.graphics.print(label, up_cx + tri + gap, cy - lh / 2)
	love.graphics.setColor(r, g, b, page < total and 1 or 0.30)
	love.graphics.polygon("fill", dn_cx, cy + tri, dn_cx - tri, cy - tri, dn_cx + tri, cy - tri)

	M.popup_prev_rect = { x = up_cx - tri - 8, y = cy - tri - 8, w = tri * 2 + 16, h = tri * 2 + 16 }
	M.popup_next_rect = { x = dn_cx - tri - 8, y = cy - tri - 8, w = tri * 2 + 16, h = tri * 2 + 16 }
end

-- Trailing blank lines in an item's `content` string count as real lines when
-- wrapping, so one stray newline can push a document over a page boundary and
-- mint a page that renders as pure whitespace. Drop them before measuring.
local function trim_trailing_blank(content)
	return (content:gsub("%s+$", ""))
end

-- Render `content` into (x, y, w, h) with pagination. When it fits on one page
-- it draws exactly as an unpaginated printf did; when it overflows, it reserves
-- a nav strip at the bottom, draws the current page, and shows a Prev/Next bar.
-- The current page comes from state.popup_page (default 1), clamped to the count.
local function draw_popup_body(state, content, font, x, y, w, h, text_color, nav_color)
	love.graphics.setFont(font)
	content = trim_trailing_blank(content)
	local line_h = font:getHeight()
	local _, wrapped = font:getWrap(content, w)

	-- Does it fit without a nav strip? If so, render it exactly as before.
	if #wrapped <= math.max(1, math.floor(h / line_h)) then
		M.popup_page_count = 1
		M.popup_prev_rect = nil
		M.popup_next_rect = nil
		love.graphics.setScissor(x, y, w, h)
		love.graphics.setColor(text_color)
		love.graphics.printf(content, x, y, w, "left")
		love.graphics.setScissor()
		return
	end

	local body_h = h - POPUP_NAV_H
	local per = math.max(1, math.floor(body_h / line_h))
	local total = math.max(1, math.ceil(#wrapped / per))
	local page = math.max(1, math.min(math.floor(state.popup_page or 1), total))
	M.popup_page_count = total

	love.graphics.setScissor(x, y, w, body_h)
	love.graphics.setColor(text_color)
	local start_i = (page - 1) * per
	local yy = y
	for i = start_i + 1, math.min(start_i + per, #wrapped) do
		love.graphics.printf(wrapped[i], x, yy, w, "left")
		yy = yy + line_h
	end
	love.graphics.setScissor()

	draw_page_nav(x, y + body_h, w, page, total, nav_color)
end

-- Render preformatted monospace `content` into (x, y, w, h): honor manual line
-- breaks instead of word-wrapping, and shrink the font uniformly so the widest
-- line fits `w` (never enlarge). Keeps ASCII columns and indentation intact for
-- computer-log popups. Paginates vertically exactly like draw_popup_body.
local function draw_popup_pre(state, content, font, x, y, w, h, text_color, nav_color)
	love.graphics.setFont(font)
	content = trim_trailing_blank(content)

	-- Split into physical lines, preserving blanks so vertical spacing survives.
	local rows = {}
	for line in (content .. "\n"):gmatch("(.-)\n") do
		rows[#rows + 1] = line
	end

	-- Uniform scale so the widest line fits the available width (shrink only).
	local maxw = 1
	for _, line in ipairs(rows) do
		local lw = font:getWidth(line)
		if lw > maxw then maxw = lw end
	end
	local scale = math.min(1, w / maxw)
	local line_h = font:getHeight() * scale

	local function draw_rows(start_i, count, oy)
		local yy = oy
		love.graphics.setColor(text_color)
		for i = start_i, math.min(start_i + count - 1, #rows) do
			love.graphics.print(rows[i], x, yy, 0, scale, scale)
			yy = yy + line_h
		end
	end

	-- Fits without a nav strip?
	if #rows <= math.max(1, math.floor(h / line_h)) then
		M.popup_page_count = 1
		M.popup_prev_rect = nil
		M.popup_next_rect = nil
		love.graphics.setScissor(x, y, w, h)
		draw_rows(1, #rows, y)
		love.graphics.setScissor()
		return
	end

	local body_h = h - POPUP_NAV_H
	local per = math.max(1, math.floor(body_h / line_h))
	local total = math.max(1, math.ceil(#rows / per))
	local page = math.max(1, math.min(math.floor(state.popup_page or 1), total))
	M.popup_page_count = total

	love.graphics.setScissor(x, y, w, body_h)
	draw_rows((page - 1) * per + 1, per, y)
	love.graphics.setScissor()

	draw_page_nav(x, y + body_h, w, page, total, nav_color)
end

local POPUP_MARGIN = 12 -- breathing room between a popup and the window edge

-- Popup documents are authored at fixed pixel sizes, but the window can be as
-- small as 800x500 (conf.lua) — at which point a 580px-tall document overhangs
-- the bottom edge and takes its Close button off-screen with it. Shrink the
-- whole popup uniformly so it always fits, preserving each style's art aspect
-- ratio. Returns the fitted size plus the scale, for art sized independently of
-- the document box. Never enlarges.
local function fit_popup(w, h)
	local scale = math.min(1,
		(M.W - POPUP_MARGIN * 2) / w,
		(M.H - POPUP_MARGIN * 2) / h)
	return w * scale, h * scale, scale
end

local function draw_popup(state)
	if not state.popup_item then
		M.popup_close_rect = nil
		M.popup_prev_rect = nil
		M.popup_next_rect = nil
		return
	end

	local item = state.popup_item
	-- Popup style is decoupled from the floor icon: an item may set `popup`
	-- to pick a popup style (e.g. "slack") while keeping `sprite` for its
	-- room-view icon.
	local sprite = item.popup or item.sprite
	local BTN_W = 160 -- wide enough for "Close  [Esc]" in the pixel font
	local BTN_H = 34

	-- Title helper (shared by all three styles)
	local raw_title = item.filename:gsub("%.txt$", ""):gsub("_", " ")
	local title = raw_title:gsub("(%a)([%w_']*)", function(a, b)
		return a:upper() .. b:lower()
	end)

	love.graphics.setFont(M.font)

	if sprite == "book" then
		local DOC_W, DOC_H = fit_popup(440, 580)
		local BIND_W = 22
		local doc_x = (M.W - DOC_W) / 2
		local doc_y = (M.H - DOC_H) / 2

		love.graphics.setColor(0, 0, 0, 0.75)
		love.graphics.rectangle("fill", 0, 0, M.W, M.H)
		love.graphics.setColor(0, 0, 0, 0.45)
		love.graphics.rectangle("fill", doc_x + 6, doc_y + 6, DOC_W, DOC_H, 6, 6)

		local fr, fg, fb = 0.32, 0.18, 0.10
		love.graphics.setColor(fr, fg, fb)
		love.graphics.rectangle("fill", doc_x, doc_y, DOC_W, DOC_H, 6, 6)

		local parch_x = doc_x + BIND_W
		local parch_y = doc_y + 10
		local parch_w = DOC_W - BIND_W - 10
		local parch_h = DOC_H - 20 - 48
		love.graphics.setColor(0.93, 0.89, 0.82)
		love.graphics.rectangle("fill", parch_x, parch_y, parch_w, parch_h, 3, 3)
		love.graphics.setColor(0.70, 0.58, 0.38, 0.25)
		love.graphics.setLineWidth(3)
		love.graphics.rectangle("line", parch_x, parch_y, parch_w, parch_h, 3, 3)
		love.graphics.setColor(0, 0, 0, 0.08)
		love.graphics.setLineWidth(8)
		love.graphics.rectangle("line", parch_x + 4, parch_y + 4, parch_w - 8, parch_h - 8, 3, 3)

		love.graphics.setColor(fr * 0.7, fg * 0.7, fb * 0.7)
		love.graphics.rectangle("fill", doc_x, doc_y, BIND_W, DOC_H, 6, 6)
		love.graphics.setColor(1, 1, 1, 0.35)
		love.graphics.setLineWidth(1)
		love.graphics.line(doc_x + BIND_W, doc_y, doc_x + BIND_W, doc_y + DOC_H)

		love.graphics.setColor(0.35, 0.20, 0.08)
		love.graphics.printf(title, parch_x + 8, parch_y + 10, parch_w - 16, "center")
		local divider_y = parch_y + 10 + M.font:getHeight() + 8
		love.graphics.setColor(0.55, 0.40, 0.20, 0.50)
		love.graphics.setLineWidth(1)
		love.graphics.line(parch_x + 8, divider_y, parch_x + parch_w - 8, divider_y)

		draw_popup_body(state, item.content, M.font_handwriting or M.font,
			parch_x + 12, divider_y + 8, parch_w - 24, (parch_y + parch_h) - (divider_y + 8) - 6,
			{ 0.18, 0.12, 0.06 }, { 0.35, 0.20, 0.08 })
		love.graphics.setFont(M.font)

		local btn_x = doc_x + (DOC_W - BTN_W) / 2
		local btn_y = doc_y + DOC_H - BTN_H - 10
		love.graphics.setColor(fr * 1.15, fg * 1.15, fb * 1.15)
		love.graphics.rectangle("fill", btn_x, btn_y, BTN_W, BTN_H, 4, 4)
		love.graphics.setColor(0.97, 0.90, 0.72)
		love.graphics.printf("Close  [Esc]", btn_x, btn_y + (BTN_H - M.font:getHeight()) / 2, BTN_W, "center")
		M.popup_close_rect = { x = btn_x, y = btn_y, w = BTN_W, h = BTN_H }
	elseif sprite == "scroll" then
		local DOC_W, DOC_H = fit_popup(440, 580)
		local BIND_W = 36
		local doc_x = (M.W - DOC_W) / 2
		local doc_y = (M.H - DOC_H) / 2

		love.graphics.setColor(0, 0, 0, 0.75)
		love.graphics.rectangle("fill", 0, 0, M.W, M.H)
		love.graphics.setColor(0, 0, 0, 0.45)
		love.graphics.rectangle("fill", doc_x + 6, doc_y + 6, DOC_W, DOC_H, 6, 6)

		local fr, fg, fb = 0.55, 0.32, 0.12
		love.graphics.setColor(fr, fg, fb)
		love.graphics.rectangle("fill", doc_x, doc_y, DOC_W, DOC_H, 6, 6)

		local parch_x = doc_x + BIND_W
		local parch_y = doc_y + 10
		local parch_w = DOC_W - BIND_W - 10
		local parch_h = DOC_H - 20 - 48
		love.graphics.setColor(0.97, 0.94, 0.84)
		love.graphics.rectangle("fill", parch_x, parch_y, parch_w, parch_h, 3, 3)
		love.graphics.setColor(0.70, 0.58, 0.38, 0.25)
		love.graphics.setLineWidth(3)
		love.graphics.rectangle("line", parch_x, parch_y, parch_w, parch_h, 3, 3)
		love.graphics.setColor(0, 0, 0, 0.08)
		love.graphics.setLineWidth(8)
		love.graphics.rectangle("line", parch_x + 4, parch_y + 4, parch_w - 8, parch_h - 8, 3, 3)

		local hole_zone_top = parch_y + 10
		local hole_zone_bottom = parch_y + parch_h - 10
		local step = (hole_zone_bottom - hole_zone_top) / 9
		for i = 0, 9 do
			local hx = doc_x + BIND_W / 2
			local hy = hole_zone_top + i * step
			love.graphics.setColor(0.15, 0.06, 0.04, 0.9)
			love.graphics.circle("fill", hx, hy, 6)
			love.graphics.setColor(0.72, 0.18, 0.12, 0.8)
			love.graphics.circle("fill", hx, hy, 4)
			love.graphics.setColor(0.90, 0.35, 0.25, 0.5)
			love.graphics.circle("fill", hx - 1, hy - 1, 2)
		end

		love.graphics.setColor(0.35, 0.20, 0.08)
		love.graphics.printf(title, parch_x + 8, parch_y + 10, parch_w - 16, "center")
		local divider_y = parch_y + 10 + M.font:getHeight() + 8
		love.graphics.setColor(0.55, 0.40, 0.20, 0.50)
		love.graphics.setLineWidth(1)
		love.graphics.line(parch_x + 8, divider_y, parch_x + parch_w - 8, divider_y)

		draw_popup_body(state, item.content, M.font_handwriting or M.font,
			parch_x + 12, divider_y + 8, parch_w - 24, (parch_y + parch_h) - (divider_y + 8) - 6,
			{ 0.18, 0.12, 0.06 }, { 0.35, 0.20, 0.08 })
		love.graphics.setFont(M.font)

		local btn_x = doc_x + (DOC_W - BTN_W) / 2
		local btn_y = doc_y + DOC_H - BTN_H - 10
		love.graphics.setColor(fr * 1.15, fg * 1.15, fb * 1.15)
		love.graphics.rectangle("fill", btn_x, btn_y, BTN_W, BTN_H, 4, 4)
		love.graphics.setColor(0.97, 0.90, 0.72)
		love.graphics.printf("Close  [Esc]", btn_x, btn_y + (BTN_H - M.font:getHeight()) / 2, BTN_W, "center")
		M.popup_close_rect = { x = btn_x, y = btn_y, w = BTN_W, h = BTN_H }
	elseif sprite == "laptop" then
		-- Digital evidence (logs, reports, on-screen files): an enlarged laptop
		-- with the file rendered onto its screen in a terminal style. No
		-- handwriting font — that is reserved for genuinely hand-written notes.
		local POP = fit_popup(640, 640)
		local pop_x = (M.W - POP) / 2
		local pop_y = (M.H - POP) / 2

		love.graphics.setColor(0, 0, 0, 0.80)
		love.graphics.rectangle("fill", 0, 0, M.W, M.H)

		-- Laptop art first (screen occupies roughly the top ~57% of the sprite).
		local spr = M.sprites.laptop
		if spr then
			love.graphics.setColor(1, 1, 1)
			love.graphics.draw(spr.img, pop_x, pop_y, 0,
				POP / spr.img:getWidth(), POP / spr.img:getHeight())
		end

		-- Screen glass within the laptop art, measured from laptop.png (64x64):
		-- x 9..55, y 5..33  ->  fractions below. The dark fill covers the glass
		-- exactly so the terminal text lines up with the laptop's screen.
		local scr_x = pop_x + POP * 0.141
		local scr_y = pop_y + POP * 0.078
		local scr_w = POP * 0.719
		local scr_h = POP * 0.438
		love.graphics.setColor(0.05, 0.07, 0.10, 0.94)
		love.graphics.rectangle("fill", scr_x, scr_y, scr_w, scr_h)
		if not spr then
			love.graphics.setColor(0.16, 0.18, 0.22)
			love.graphics.setLineWidth(2)
			love.graphics.rectangle("line", scr_x, scr_y, scr_w, scr_h)
		end

		-- Filename header + divider, then the body — in the computer-log font.
		local pad = 16
		local line_h = M.font_mono:getHeight()
		love.graphics.setFont(M.font_mono)
		love.graphics.setColor(0.55, 0.95, 0.55) -- terminal-green filename
		love.graphics.print(item.filename, scr_x + pad, scr_y + pad)
		love.graphics.setColor(0.30, 0.55, 0.30)
		love.graphics.setLineWidth(1)
		local div_y = scr_y + pad + line_h + 6
		love.graphics.line(scr_x + pad, div_y, scr_x + scr_w - pad, div_y)

		draw_popup_pre(state, item.content, M.font_mono,
			scr_x + pad, div_y + 10, scr_w - pad * 2, (scr_y + scr_h) - (div_y + 10) - 4,
			{ 0.82, 0.88, 0.84 }, { 0.55, 0.85, 0.60 })

		local btn_x = pop_x + (POP - BTN_W) / 2
		local btn_y = pop_y + POP - BTN_H - 6
		love.graphics.setColor(0.16, 0.20, 0.26)
		love.graphics.rectangle("fill", btn_x, btn_y, BTN_W, BTN_H, 4, 4)
		love.graphics.setColor(0.85, 0.90, 0.86)
		love.graphics.printf("Close  [Esc]", btn_x, btn_y + (BTN_H - M.font:getHeight()) / 2, BTN_W, "center")
		M.popup_close_rect = { x = btn_x, y = btn_y, w = BTN_W, h = BTN_H }
	elseif sprite == "slack" then
		-- Slack popup: the slack-bg pixel-art chrome scaled up, chat text drawn
		-- into the message column. Falls back to a plain dark panel if the
		-- background image failed to load.
		-- 1.6 aspect, matching slack-bg.png (192×120)
		local POP_W, POP_H = fit_popup(680, 425)
		local pop_x = (M.W - POP_W) / 2
		local pop_y = (M.H - POP_H) / 2

		love.graphics.setColor(0, 0, 0, 0.78)
		love.graphics.rectangle("fill", 0, 0, M.W, M.H)

		if M.slack_bg then
			love.graphics.setColor(1, 1, 1)
			love.graphics.draw(M.slack_bg, pop_x, pop_y, 0,
				POP_W / M.slack_bg:getWidth(), POP_H / M.slack_bg:getHeight())
		else
			love.graphics.setColor(0.15, 0.11, 0.18)
			love.graphics.rectangle("fill", pop_x, pop_y, POP_W, POP_H, 6, 6)
		end

		-- Message column (right of the purple sidebar, below the header bar).
		local col_x = pop_x + POP_W * 0.30
		local col_y = pop_y + POP_H * 0.20
		local col_w = POP_W * 0.66
		local col_h = POP_H * 0.60

		-- Channel / DM title above the message column (computer-log font).
		love.graphics.setFont(M.font_mono)
		love.graphics.setColor(0.93, 0.93, 0.96)
		love.graphics.print(item.channel or title, col_x, pop_y + POP_H * 0.07)

		-- Dark backing so chat text stays legible over the pixel art.
		love.graphics.setColor(0.10, 0.09, 0.13, 0.72)
		love.graphics.rectangle("fill", col_x - 8, col_y - 6, col_w + 16, col_h + 12, 4, 4)

		draw_popup_body(state, item.content, M.font_mono,
			col_x, col_y, col_w, col_h,
			{ 0.90, 0.91, 0.94 }, { 0.80, 0.82, 0.92 })

		local btn_x = pop_x + (POP_W - BTN_W) / 2
		local btn_y = pop_y + POP_H - BTN_H - 12
		love.graphics.setColor(0.30, 0.16, 0.36)
		love.graphics.rectangle("fill", btn_x, btn_y, BTN_W, BTN_H, 4, 4)
		love.graphics.setColor(0.95, 0.92, 0.97)
		love.graphics.printf("Close  [Esc]", btn_x, btn_y + (BTN_H - M.font:getHeight()) / 2, BTN_W, "center")
		M.popup_close_rect = { x = btn_x, y = btn_y, w = BTN_W, h = BTN_H }
	else
		-- Object popup: large sprite image + text box at the bottom
		local POP_W, POP_H, pop_scale = fit_popup(420, 500)
		local IMG_SZ = 200 * pop_scale -- shrink the art too, so the text box survives
		local PAD = 16
		local pop_x = (M.W - POP_W) / 2
		local pop_y = (M.H - POP_H) / 2

		love.graphics.setColor(0, 0, 0, 0.80)
		love.graphics.rectangle("fill", 0, 0, M.W, M.H)
		love.graphics.setColor(0, 0, 0, 0.50)
		love.graphics.rectangle("fill", pop_x + 6, pop_y + 6, POP_W, POP_H, 6, 6)

		love.graphics.setColor(0.14, 0.13, 0.18)
		love.graphics.rectangle("fill", pop_x, pop_y, POP_W, POP_H, 6, 6)
		love.graphics.setColor(0.35, 0.30, 0.45, 0.60)
		love.graphics.setLineWidth(1)
		love.graphics.rectangle("line", pop_x, pop_y, POP_W, POP_H, 6, 6)

		love.graphics.setColor(0.85, 0.80, 0.70)
		love.graphics.printf(title, pop_x + PAD, pop_y + PAD, POP_W - PAD * 2, "center")

		local img_x = pop_x + (POP_W - IMG_SZ) / 2
		local img_y = pop_y + PAD + M.font:getHeight() + PAD
		love.graphics.setColor(0.10, 0.09, 0.14)
		love.graphics.rectangle("fill", img_x, img_y, IMG_SZ, IMG_SZ, 4, 4)
		love.graphics.setColor(0.30, 0.25, 0.40, 0.50)
		love.graphics.setLineWidth(1)
		love.graphics.rectangle("line", img_x, img_y, IMG_SZ, IMG_SZ, 4, 4)
		local spr = M.sprites[sprite]
		if spr then
			local scale = IMG_SZ / spr.img:getWidth()
			love.graphics.setColor(1, 1, 1)
			love.graphics.draw(spr.img, img_x, img_y, 0, scale, scale)
		end

		local box_x = pop_x + PAD
		local box_y = img_y + IMG_SZ + PAD
		local box_w = POP_W - PAD * 2
		local box_h = POP_H - (box_y - pop_y) - BTN_H - PAD * 2
		love.graphics.setColor(0.08, 0.07, 0.12)
		love.graphics.rectangle("fill", box_x, box_y, box_w, box_h, 4, 4)
		love.graphics.setColor(0.30, 0.25, 0.40, 0.40)
		love.graphics.setLineWidth(1)
		love.graphics.rectangle("line", box_x, box_y, box_w, box_h, 4, 4)
		draw_popup_body(state, item.content, M.font,
			box_x + 8, box_y + 8, box_w - 16, box_h - 16,
			{ 0.78, 0.74, 0.66 }, { 0.72, 0.68, 0.82 })

		local btn_x = pop_x + (POP_W - BTN_W) / 2
		local btn_y = pop_y + POP_H - BTN_H - PAD
		love.graphics.setColor(0.28, 0.22, 0.38)
		love.graphics.rectangle("fill", btn_x, btn_y, BTN_W, BTN_H, 4, 4)
		love.graphics.setColor(0.85, 0.80, 0.70)
		love.graphics.printf("Close  [Esc]", btn_x, btn_y + (BTN_H - M.font:getHeight()) / 2, BTN_W, "center")
		M.popup_close_rect = { x = btn_x, y = btn_y, w = BTN_W, h = BTN_H }
	end
end

local ROOM_BORDER = 16 -- pixel-art frame thickness around the room view

-- A chunky beveled pixel frame around the room rect: dark outer/inner outlines,
-- a wood-tone body, and a top-left highlight / bottom-right shadow bevel, plus
-- little corner studs. Drawn in the margin left by insetting the room canvas.
local function draw_room_border(x, y, w, h)
	local B = ROOM_BORDER
	local u = 3 -- pixel unit for outlines / bevel
	local edge = { 0.10, 0.08, 0.06 }
	local body = { 0.42, 0.30, 0.18 }
	local hi = { 0.64, 0.48, 0.28 }
	local sh = { 0.24, 0.16, 0.09 }

	-- body bands framing the opening (top / bottom / left / right)
	love.graphics.setColor(body)
	love.graphics.rectangle("fill", x, y, w, B)
	love.graphics.rectangle("fill", x, y + h - B, w, B)
	love.graphics.rectangle("fill", x, y, B, h)
	love.graphics.rectangle("fill", x + w - B, y, B, h)

	-- outer dark outline
	love.graphics.setColor(edge)
	love.graphics.rectangle("fill", x, y, w, u)
	love.graphics.rectangle("fill", x, y + h - u, w, u)
	love.graphics.rectangle("fill", x, y, u, h)
	love.graphics.rectangle("fill", x + w - u, y, u, h)

	-- bevel: highlight along top + left, shadow along bottom + right
	love.graphics.setColor(hi)
	love.graphics.rectangle("fill", x + u, y + u, w - 2 * u, u)
	love.graphics.rectangle("fill", x + u, y + u, u, h - 2 * u)
	love.graphics.setColor(sh)
	love.graphics.rectangle("fill", x + u, y + h - 2 * u, w - 2 * u, u)
	love.graphics.rectangle("fill", x + w - 2 * u, y + u, u, h - 2 * u)

	-- inner dark outline around the opening
	love.graphics.setColor(edge)
	local ix, iy, iw, ih = x + B - u, y + B - u, w - 2 * (B - u), h - 2 * (B - u)
	love.graphics.rectangle("fill", ix, iy, iw, u)
	love.graphics.rectangle("fill", ix, iy + ih - u, iw, u)
	love.graphics.rectangle("fill", ix, iy, u, ih)
	love.graphics.rectangle("fill", ix + iw - u, iy, u, ih)

	-- corner studs
	local s = 5
	love.graphics.setColor(hi)
	for _, c in ipairs({ { x + u + 1, y + u + 1 }, { x + w - u - 1 - s, y + u + 1 },
		{ x + u + 1, y + h - u - 1 - s }, { x + w - u - 1 - s, y + h - u - 1 - s } }) do
		love.graphics.rectangle("fill", c[1], c[2], s, s)
		love.graphics.setColor(edge)
		love.graphics.rectangle("fill", c[1] + s - 1, c[2] + s - 1, 1, 1)
		love.graphics.setColor(hi)
	end
end

function M.draw(state, term, best, vim)
	-- Render the room view into its own virtual-resolution canvas first.
	-- Restore to whatever canvas was active before (usually the screen, but the
	-- CRT intro captures this whole frame into M.crt_canvas), not forced to nil.
	local prev_canvas = love.graphics.getCanvas()
	if not M.terminal_only and not vim then
		love.graphics.setCanvas(M.room_canvas)
		love.graphics.clear()
		draw_room_view(state)
		love.graphics.setCanvas(prev_canvas)
	end

	-- Now draw at native window resolution.
	love.graphics.setColor(C.bg)
	love.graphics.rectangle("fill", 0, 0, M.W, M.H)
	draw_terminal(state, term, vim ~= nil)

	-- The notes editor replaces the room view outright; in terminal-only mode it
	-- takes the half of the window the terminal just gave up.
	if vim then
		draw_vim_view(vim)
	end

	-- Room view, inset to leave room for a pixel-art frame around it. Skipped
	-- entirely in terminal-only mode, and while vim has the panel.
	if not M.terminal_only and not vim then
		local B = ROOM_BORDER
		love.graphics.setColor(1, 1, 1)
		love.graphics.draw(M.room_canvas, M.room_x + B, M.room_y + B, 0,
			(M.room_w - 2 * B) / ROOM_VW, (M.room_h - 2 * B) / ROOM_VH)
		draw_room_border(M.room_x, M.room_y, M.room_w, M.room_h)
	end

	draw_status_bar(state)
	if state.won then
		draw_win_screen(state, best)
	end
	draw_popup(state)
end

return M
