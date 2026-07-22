-- audio.lua — SFX and room ambience. No soundtrack.
--
-- Plain `M.` module, no metatables, matching vim.lua/world.lua. Every public
-- function is a no-op when love.audio doesn't exist, which is the case under
-- `lua test/run.lua` and headless/engine.lua (see HAVE_AUDIO below) — those
-- environments run the command layer directly, and a bare love.audio.* call
-- there would crash the whole suite.

local M = {}

local HAVE_AUDIO = (type(love) == "table") and (love.audio ~= nil)
local HAVE_FS = (type(love) == "table") and (love.filesystem ~= nil)

M.enabled = true
M.volume_scale = 1.0 -- user-controlled master slider (`volume <0-100>`), persisted
M.sfx_volume = 1.0 -- group baseline for one-shot SFX
M.ambience_volume = 0.6 -- group baseline for room ambience beds

-- Set by screens/game.lua for a terminal-only run (no room view): audio is
-- entirely off for that run, independent of the player's own mute/volume
-- setting, so unmuting mid-run can't turn it back on by accident.
local suppressed = false

local SETTINGS_PATH = "settings.txt"

-- id -> how to play it. `files` is a list; one is chosen at random per play,
-- which is what stops repeated keystrokes sounding like a machine gun.
M.SOUNDS = {
	key_press = {
		files = { "assets/audio/ui/key_1.ogg", "assets/audio/ui/key_2.ogg", "assets/audio/ui/key_3.ogg" },
		volume = 0.35,
		pitch = { 0.94, 1.06 },
		group = "typing",
	},
	key_enter = { files = { "assets/audio/ui/enter.ogg" }, volume = 0.5, group = "typing" },
	key_back = { files = { "assets/audio/ui/back.ogg" }, volume = 0.3, group = "typing" },
	tab_one = { files = { "assets/audio/ui/tick.ogg" }, volume = 0.3 },
	tab_many = { files = { "assets/audio/ui/tick2.ogg" }, volume = 0.3 },
	error_tick = { files = { "assets/audio/ui/error.ogg" }, volume = 0.45 },
	crt_on = { files = { "assets/audio/ui/crt_on.ogg" }, volume = 0.7, group = "crt" },
	crt_off = { files = { "assets/audio/ui/crt_off.ogg" }, volume = 0.7, group = "crt" },
	bell = { files = { "assets/audio/ui/bell.ogg" }, volume = 0.6 },
	write_ok = { files = { "assets/audio/ui/write_ok.ogg" }, volume = 0.45 },
	mode_tick = { files = { "assets/audio/ui/mode_tick.ogg" }, volume = 0.25 },
	page_turn = { files = { "assets/audio/ui/page_turn.ogg" }, volume = 0.4 },
	unlock_ping = { files = { "assets/audio/ui/unlock_ping.ogg" }, volume = 0.5 },
	win = { files = { "assets/audio/ui/win.ogg" }, volume = 0.8 },
	record = { files = { "assets/audio/ui/record.ogg" }, volume = 0.8 },

	paper_open = { files = { "assets/audio/world/paper_open.ogg" }, volume = 0.5 },
	paper_close = { files = { "assets/audio/world/paper_close.ogg" }, volume = 0.5 },
	book_open = { files = { "assets/audio/world/book_open.ogg" }, volume = 0.5 },
	book_close = { files = { "assets/audio/world/book_close.ogg" }, volume = 0.5 },
	screen_on = { files = { "assets/audio/world/screen_on.ogg" }, volume = 0.5 },
	screen_off = { files = { "assets/audio/world/screen_off.ogg" }, volume = 0.5 },
	slack_blip = { files = { "assets/audio/world/slack_blip.ogg" }, volume = 0.5 },
	popup_open = { files = { "assets/audio/world/popup_open.ogg" }, volume = 0.5 },
	popup_close = { files = { "assets/audio/world/popup_close.ogg" }, volume = 0.5 },

	step = { files = { "assets/audio/world/step.ogg" }, volume = 0.4 },
	door_new = { files = { "assets/audio/world/door_new.ogg" }, volume = 0.55 },
	locked = { files = { "assets/audio/world/locked.ogg" }, volume = 0.5 },
	badge_ok = { files = { "assets/audio/world/badge_ok.ogg" }, volume = 0.55 },
	search = { files = { "assets/audio/world/search.ogg" }, volume = 0.45 },
	edit_commit = { files = { "assets/audio/world/edit_commit.ogg" }, volume = 0.45 },
	move = { files = { "assets/audio/world/move.ogg" }, volume = 0.4 },
	warn = { files = { "assets/audio/world/warn.ogg" }, volume = 0.6 },
	destroy = { files = { "assets/audio/world/destroy.ogg" }, volume = 0.9 },
	unlock_heavy = { files = { "assets/audio/world/unlock_heavy.ogg" }, volume = 0.8 },
	unlock_fail = { files = { "assets/audio/world/unlock_fail.ogg" }, volume = 0.55 },
}

-- Popup open/close keyed by the item's sprite. THIS is the table to edit to
-- change how a whole class of evidence sounds. Key = `item.popup or item.sprite`
-- (render.lua resolves the popup style the same way, so audio and visuals stay
-- in agreement by construction). New sprite kinds inherit `default` silently.
M.SPRITE_SOUNDS = {
	scroll = { open = "paper_open", close = "paper_close" },
	laptop = { open = "screen_on", close = "screen_off" },
	book = { open = "book_open", close = "book_close" },
	slack = { open = "slack_blip", close = "screen_off" },
	default = { open = "popup_open", close = "popup_close" },
}

-- Per-room ambience loop, crossfaded on `cd` (see M.set_room).
M.ROOM_AMBIENCE = {
	foyer = "assets/audio/amb/room_tone.ogg",
	server_room = "assets/audio/amb/server_fans.ogg",
	cellar = "assets/audio/amb/cellar_drip.ogg",
	sunroom = "assets/audio/amb/birds_glass.ogg",
	garage = "assets/audio/amb/compressor.ogg",
	den = "assets/audio/amb/party_muffled.ogg",
	game_room = "assets/audio/amb/arcade_hum.ogg",
	home_office = "assets/audio/amb/room_tone.ogg",
	[".closet"] = "assets/audio/amb/room_tone.ogg",
}

-- Prototype "static" Sources, cloned per play so overlapping keystrokes don't
-- cut each other off. Built by M.load(); nil (silently no-op) until then.
local proto = {}

-- group -> list of currently-playing clones, so stop_group can cut them off.
local active_by_group = {}

-- Cached "stream" Sources for ambience beds, keyed by file path.
local ambience_sources = {}

local amb = {
	current = nil, -- Source
	current_path = nil,
	fading_out = nil, -- Source
	fade_t = 0,
	fade_dur = 0.4,
	ducked = false,
}

local function load_settings()
	if not HAVE_FS then
		return
	end
	if not love.filesystem.getInfo(SETTINGS_PATH) then
		return
	end
	local content = love.filesystem.read(SETTINGS_PATH)
	if not content or content == "" then
		return
	end
	-- Bare 1-arg `load` (matching save.lua's convert_string_to_state): some
	-- LuaJIT builds (the web target among them) don't support the 5.2-style
	-- 4-arg load(str, chunkname, mode, env) and throw "function expected,
	-- got string" instead of just erroring on the content.
	local ok_load, chunk = pcall(load, content)
	if not ok_load or not chunk then
		return
	end
	local ok, value = pcall(chunk)
	if ok and type(value) == "table" then
		if type(value.enabled) == "boolean" then
			M.enabled = value.enabled
		end
		if type(value.volume_scale) == "number" then
			M.volume_scale = value.volume_scale
		end
	end
end

local function save_settings()
	if not HAVE_FS then
		return
	end
	local data = string.format(
		"return { enabled = %s, volume_scale = %.4f }",
		tostring(M.enabled),
		M.volume_scale
	)
	love.filesystem.write(SETTINGS_PATH, data)
end

-- Build every prototype Source from the registry, and restore the persisted
-- mute/volume setting. Safe to call once at startup; a no-op headless.
function M.load()
	if not HAVE_AUDIO then
		return
	end
	proto = {}
	for id, def in pairs(M.SOUNDS) do
		local list = {}
		for _, path in ipairs(def.files) do
			local ok, src = pcall(love.audio.newSource, path, "static")
			if ok and src then
				table.insert(list, src)
			end
		end
		proto[id] = list
	end
	load_settings()
end

-- Drop clones that have finished playing so the active-group lists stay small.
local function untrack_finished()
	for group, list in pairs(active_by_group) do
		local kept = {}
		for _, src in ipairs(list) do
			if src:isPlaying() then
				table.insert(kept, src)
			end
		end
		active_by_group[group] = kept
	end
end

-- opts = { volume, pitch, loop }, all optional overrides of the registry entry.
function M.play(id, opts)
	if not HAVE_AUDIO or not M.enabled or suppressed then
		return
	end
	local def = M.SOUNDS[id]
	if not def then
		return
	end
	local list = proto[id]
	if not list or #list == 0 then
		return
	end
	opts = opts or {}

	local src = list[math.random(#list)]:clone()
	local vol = (opts.volume or def.volume or 1.0) * M.sfx_volume * M.volume_scale
	src:setVolume(vol)

	local pitch = opts.pitch
	if pitch == nil and def.pitch then
		pitch = def.pitch[1] + math.random() * (def.pitch[2] - def.pitch[1])
	end
	if pitch then
		src:setPitch(pitch)
	end

	src:setLooping(opts.loop or false)
	src:play()

	if def.group then
		active_by_group[def.group] = active_by_group[def.group] or {}
		table.insert(active_by_group[def.group], src)
	end
	return src
end

-- Look up SPRITE_SOUNDS[sprite] (or .default) and play the id for `event`
-- ("open" | "close"). New sprite kinds without an entry inherit the default.
function M.play_sprite(sprite, event)
	local pair = M.SPRITE_SOUNDS[sprite] or M.SPRITE_SOUNDS.default
	local id = pair and pair[event]
	if id then
		M.play(id)
	end
end

-- Cut off every currently-playing sound tagged with `group` (e.g. "typing",
-- "crt"). Used to kill in-flight keystroke sounds on a skip.
function M.stop_group(group)
	if not HAVE_AUDIO then
		return
	end
	local list = active_by_group[group]
	if not list then
		return
	end
	for _, src in ipairs(list) do
		if src:isPlaying() then
			src:stop()
		end
	end
	active_by_group[group] = {}
end

local function get_ambience_source(path)
	if not path then
		return nil
	end
	if not ambience_sources[path] then
		local ok, src = pcall(love.audio.newSource, path, "stream")
		if ok and src then
			src:setLooping(true)
			ambience_sources[path] = src
		end
	end
	return ambience_sources[path]
end

-- Crossfade the ambience bed to whatever ROOM_AMBIENCE[room_id] points at.
-- A room with no entry (or the same bed already playing) is a no-op.
function M.set_room(room_id)
	if not HAVE_AUDIO or suppressed then
		return
	end
	local path = M.ROOM_AMBIENCE[room_id]
	if path == amb.current_path then
		return
	end
	if amb.current then
		amb.fading_out = amb.current
	end
	amb.current_path = path
	amb.current = get_ambience_source(path)
	amb.fade_t = 0
	if amb.current then
		amb.current:setVolume(0)
		if not amb.current:isPlaying() then
			amb.current:play()
		end
	end
end

-- Lower the ambience bed while a popup/document is up; restore on close.
function M.duck(active)
	amb.ducked = active
end

-- Drives the ambience crossfade. Call once per frame from the game screen.
function M.update(dt)
	if not HAVE_AUDIO then
		return
	end
	untrack_finished()

	amb.fade_t = math.min(amb.fade_dur, amb.fade_t + dt)
	local frac = amb.fade_dur > 0 and (amb.fade_t / amb.fade_dur) or 1
	local target = M.ambience_volume * M.volume_scale * (amb.ducked and 0.35 or 1.0)
	if not M.enabled or suppressed then
		target = 0
	end

	if amb.current then
		amb.current:setVolume(target * frac)
	end
	if amb.fading_out then
		amb.fading_out:setVolume(math.max(0, target * (1 - frac)))
		if frac >= 1 then
			amb.fading_out:stop()
			amb.fading_out = nil
		end
	end
end

-- Toggle mute (used by the `mute` command). Stops everything in flight when
-- muting so nothing keeps ringing; ambience resumes from the next `cd` when
-- unmuted.
function M.set_enabled(value)
	M.enabled = value
	if not value and HAVE_AUDIO then
		for _, src in pairs(ambience_sources) do
			if src:isPlaying() then
				src:stop()
			end
		end
		amb.current, amb.current_path, amb.fading_out = nil, nil, nil
		for group in pairs(active_by_group) do
			M.stop_group(group)
		end
	end
	save_settings()
end

-- Used by the `volume <0-100>` command.
function M.set_volume(pct)
	M.volume_scale = math.max(0, math.min(100, pct)) / 100
	save_settings()
end

-- Silence this run entirely (terminal-only mode has no room view, so no
-- ambience, and no SFX either). Independent of M.enabled / settings.txt.
function M.set_suppressed(value)
	suppressed = value
	if value then
		M.stop_all()
	end
end

-- Stop every currently-playing sound: ambience beds and every SFX group.
-- Called when leaving the game screen (quit to title) so nothing keeps
-- ringing over a screen that no longer owns it.
function M.stop_all()
	if not HAVE_AUDIO then
		return
	end
	for _, src in pairs(ambience_sources) do
		if src:isPlaying() then
			src:stop()
		end
	end
	amb.current, amb.current_path, amb.fading_out = nil, nil, nil
	for group in pairs(active_by_group) do
		M.stop_group(group)
	end
end

return M
