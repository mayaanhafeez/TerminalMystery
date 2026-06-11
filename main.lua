-- main.lua
-- LÖVE callbacks, input handling, save-file I/O. The thin glue layer that
-- ties world.lua, commands.lua and render.lua together.

Screen = require("screen")
GameScreen = require("screens/game")

Screen.register(GameScreen)


function love.load()
	love.keyboard.setKeyRepeat(true)
	Render.load()
  GameScreen.start_new()
  Screen.set("game")
end

-- ---------- save file ----------



-- ---------- LÖVE callbacks ----------

