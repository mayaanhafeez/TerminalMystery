Save = require("save")
Screen = require("screen")
Render = require("render")

local aspect_ratio = 0.2
local padding = 80
local center= {x = 250, y = 250}
local screen_size = {w = 500, h = 500}
local button_size = {w = ((24/9)*screen_size.w)*aspect_ratio, h = screen_size.h*aspect_ratio}
local save_data = nil
local M = {}
--place holder functions
local function load_from_save()
  save_data = Save.load_state("save_data.txt")
end

local function start_new_game()
  GameScreen.start_new()
  Screen.set("game")
end

local function get_button_position(wanted_x, wanted_y, this_button_size)
  -- converts given center position to top left corner
  local actual_position = {x = wanted_x - this_button_size.w/2, y = wanted_y - this_button_size.h/2}
  return actual_position
end

local function button_selected()
  local x,y = love.mouse.getPosition()
  for _, my_button in ipairs(M.buttons) do
    local this_button_size = my_button.size
    local button_position = my_button.position
    if x > button_position.x and x< (button_position.x + this_button_size.w) and y > button_position.y and y<(button_position.y + this_button_size.h) then
      return my_button
    end
  end
  return nil
end

local function draw_button(button)
  local button_position = button.position
  local this_button_size = button.size
  if save_data == nil and button.label == "Continue From Save" then
    love.graphics.setColor(0.5,0.5,0.5)
  else
    love.graphics.setColor(1,1,1)
  end
  love.graphics.rectangle("fill", button_position.x, button_position.y, this_button_size.w, this_button_size.h, 5)
  local label = button.label
  local font = love.graphics.getFont()
  local text_position = {x = button_position.x + (this_button_size.w - font:getWidth(label)) /2, y= button_position.y + (this_button_size.h - font:getHeight()) /2}
  love.graphics.setColor(0,0,0)
  love.graphics.print(label, text_position.x, text_position.y)
end

M.buttons = {}

function M.enter()
  save_data = Save.load_state("save_data.txt")
end

function M.draw()
  --get screen middle
  local cw,ch = love.graphics.getDimensions()
  if screen_size.w~=cw or screen_size.h~=ch then
    screen_size.w, screen_size.h = cw,ch
    center = {x = screen_size.w/2, y = screen_size.h/2}
    M.load_buttons()
  end
  love.graphics.clear(0,0,0,1)
  for _, button in ipairs(M.buttons) do
    draw_button(button)
  end
end

function M.mousepressed(_, _, mouse_button)
  local button = button_selected()
  if button ~= nil and mouse_button == 1 then
    button.action()
  end
end

function M.load_buttons()
  M.buttons = {
    {label = "Continue From Save", size = button_size, position = get_button_position(center.x, center.y - button_size.h/2 - padding, button_size), action = function() load_from_save() end},
    {label = "New Game", size = button_size, position = get_button_position(center.x, center.y , button_size), action = function() start_new_game() end},
    {label = "Back", size = button_size, position = get_button_position(center.x, center.y + padding + (button_size.h/2) , button_size), action = function() Screen.set("play") end},
  }
end

return M
