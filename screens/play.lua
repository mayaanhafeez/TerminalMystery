Screen = require("screen")
Render = require("render")
local ASPECT_RATIO = 0.2
local center = {x = 500 ,y = 500}

local function get_button_position(wanted_x, wanted_y, button_size)
  local actual_position = {x = wanted_x - button_size.w/2, y = wanted_y - button_size.h/2}
  return actual_position
end

local function get_button_size()
  local button_size
  if center.x ~= nil and center.y ~=nil then
    button_size = {w = ((24/9)*center.x)*ASPECT_RATIO, h = center.y*ASPECT_RATIO}
  else
    button_size = {w = 200,h = 150}
  end
  return button_size
end

local function button_selected()
  local x,y = love.mouse.getPosition()
  local my_button = M.buttons[1]
  local button_size = my_button.size
  local button_position = my_button.position
  if x > button_position.x and x< (button_position.x + button_size.w) and y > button_position.y and y<(button_position.y + button_size.h) then
    return my_button.label
  else
    return nil
  end
end

M = {}

M.buttons = {}

function M.draw()
  --get screen middle
  local w, h = love.graphics.getDimensions()
  center = {x = w/2, y = h/2}
  love.graphics.clear(0,0,0,1)
  local button_size = get_button_size()
  local button_position = get_button_position(center.x, center.y, button_size)
  love.graphics.rectangle("line", button_position.x, button_position.y, button_size.w, button_size.h)
  M.load_buttons()
end

function M.mousepressed(x, y, mouse_button)
  local button = button_selected()
  if button ~= nil and mouse_button == 1 then
    M.buttons[1].action()
  end
end

function M.load_buttons()
  M.buttons = {
    {label = "play", size = get_button_size(), position = get_button_position(center.x, center.y, get_button_size()), action = function() Screen.set("game") end},
    {label = "exit", action = function() love.event.quit() end},
  }
end
return M
