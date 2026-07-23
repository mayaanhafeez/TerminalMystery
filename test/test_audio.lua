-- test/test_audio.lua — registry integrity + the headless no-op guarantee.
--
-- Runs under plain `lua`, where `love` doesn't exist at all (unlike
-- headless/engine.lua, which stubs love.timer). audio.lua's HAVE_AUDIO check
-- must therefore treat a missing `love` global the same as a `love` without
-- `.audio` — this is the regression that would otherwise take out every other
-- suite the moment a command handler calls Audio.play().

local T = require("test.runner")
local Audio = require("audio")

-- -----------------------------------------------------------------------
T.suite("audio — registry integrity")

T.test("every SPRITE_SOUNDS open/close id resolves in SOUNDS", function()
    for sprite, pair in pairs(Audio.SPRITE_SOUNDS) do
        T.ok(Audio.SOUNDS[pair.open], sprite .. ".open -> " .. tostring(pair.open) .. " missing from SOUNDS")
        T.ok(Audio.SOUNDS[pair.close], sprite .. ".close -> " .. tostring(pair.close) .. " missing from SOUNDS")
    end
end)

T.test("SPRITE_SOUNDS has a default entry", function()
    T.ok(Audio.SPRITE_SOUNDS.default, "SPRITE_SOUNDS.default must exist so unknown sprites inherit it")
end)

T.test("every SOUNDS file path exists on disk", function()
    for id, def in pairs(Audio.SOUNDS) do
        for _, path in ipairs(def.files) do
            local f = io.open(path, "rb")
            T.ok(f, id .. ": " .. path .. " does not exist")
            if f then f:close() end
        end
    end
end)

T.test("every ROOM_AMBIENCE file path exists on disk", function()
    for room_id, path in pairs(Audio.ROOM_AMBIENCE) do
        local f = io.open(path, "rb")
        T.ok(f, room_id .. ": " .. path .. " does not exist")
        if f then f:close() end
    end
end)

-- -----------------------------------------------------------------------
T.suite("audio — headless no-op")

T.test("M.load is a silent no-op without love.audio", function()
    local ok = pcall(Audio.load)
    T.ok(ok, "Audio.load() must not error when love.audio is absent")
end)

T.test("M.play is a silent no-op without love.audio", function()
    local ok, result = pcall(Audio.play, "key_press")
    T.ok(ok, "Audio.play() must not error when love.audio is absent")
    T.nil_(result, "Audio.play() should return nothing headless")
end)

T.test("M.play_sprite is a silent no-op without love.audio", function()
    local ok = pcall(Audio.play_sprite, "scroll", "open")
    T.ok(ok, "Audio.play_sprite() must not error when love.audio is absent")
end)

T.test("M.play_delayed is a silent no-op without love.audio", function()
    local ok = pcall(Audio.play_delayed, "step", 0.2)
    T.ok(ok, "Audio.play_delayed() must not error when love.audio is absent")
end)

T.test("M.stop_group is a silent no-op without love.audio", function()
    local ok = pcall(Audio.stop_group, "typing")
    T.ok(ok, "Audio.stop_group() must not error when love.audio is absent")
end)

T.test("M.set_room is a silent no-op without love.audio", function()
    local ok = pcall(Audio.set_room, "foyer")
    T.ok(ok, "Audio.set_room() must not error when love.audio is absent")
end)

T.test("M.update is a silent no-op without love.audio", function()
    local ok = pcall(Audio.update, 0.016)
    T.ok(ok, "Audio.update() must not error when love.audio is absent")
end)

T.test("M.duck is safe without love.audio", function()
    local ok = pcall(Audio.duck, true)
    T.ok(ok, "Audio.duck() must not error when love.audio is absent")
    Audio.duck(false)
end)

T.test("mute/volume setters work without love.filesystem", function()
    local ok = pcall(Audio.set_enabled, false)
    T.ok(ok, "Audio.set_enabled() must not error without love.filesystem")
    Audio.set_enabled(true)
    T.eq(Audio.enabled, true)

    local ok2 = pcall(Audio.set_volume, 50)
    T.ok(ok2, "Audio.set_volume() must not error without love.filesystem")
    T.eq(Audio.volume_scale, 0.5)
    Audio.set_volume(100)
end)
