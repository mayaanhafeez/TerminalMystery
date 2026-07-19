-- main.lua
-- LÖVE callbacks, input handling, save-file I/O. The thin glue layer that
-- ties world.lua, commands.lua and render.lua together.

Screen = require("screen")
GameScreen = require("screens/game")
PlayScreen = require("screens/play")
PlayMenuScreen = require("screens/play_menu")
BootScreen = require("screens/boot")
ModeSelectScreen = require("screens/mode_select")
Render = require("render")
World = require("world")

Screen.register("play", PlayScreen)
Screen.register("game", GameScreen)
Screen.register("play_menu", PlayMenuScreen)
Screen.register("boot", BootScreen)
Screen.register("mode_select", ModeSelectScreen)

function love.load()
	love.keyboard.setKeyRepeat(true)
	Render.load()
  GameScreen.start_new()
  Screen.set("boot")
end

function love.resize(w, h)
  Render.resize(w, h)
  GameScreen.resize(w, h)
end

function love.update(dt)
  Screen.update(dt)
end

function love.draw()
  Screen.draw()
end

function love.keypressed(k)
  Screen.keypressed(k)
end

function love.mousepressed(x, y, button)
  Screen.mousepressed(x, y, button)
end

function love.textinput(t)
  Screen.text_input(t)
end
