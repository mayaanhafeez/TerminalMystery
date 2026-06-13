Screen = require("screen")
Render = require("render")

local ASPECT_RATIO = 0.2
local PADDING = 80
local CENTER= {x = 250, y = 250}
local SCREEN_SIZE = {w = 500, h = 500}
local BUTTON_SIZE = {w = ((24/9)*SCREEN_SIZE.w)*ASPECT_RATIO, h = SCREEN_SIZE.h*ASPECT_RATIO}

local function get_button_position(wanted_x, wanted_y, button_size)
  -- converts given center position to top left corner
  local actual_position = {x = wanted_x - button_size.w/2, y = wanted_y - button_size.h/2}
  return actual_position
end

local function button_selected()
  local x,y = love.mouse.getPosition()
  for _, my_button in ipairs(M.buttons) do
    local button_size = my_button.size
    local button_position = my_button.position
    if x > button_position.x and x< (button_position.x + button_size.w) and y > button_position.y and y<(button_position.y + button_size.h) then
      return my_button
    end
  end
  return nil
end

local function draw_button(button)
  local button_size = BUTTON_SIZE
  local x, y = button.position
  local button_position = button.position
  love.graphics.setColor(1,1,1)
  love.graphics.rectangle("fill", button_position.x, button_position.y, button_size.w, button_size.h, 5)
  local label = button.label
  local font = love.graphics.getFont()
  local text_position = {x = button_position.x + (button_size.w - font:getWidth(label)) /2, y= button_position.y + (button_size.h - font:getHeight()) /2}
  love.graphics.setColor(0,0,0)
  love.graphics.print(label, text_position.x, text_position.y)
end

M = {}

M.buttons = {}

function M.draw()
  --get screen middle
  W, H = love.graphics.getDimensions()
  CENTER = {x = W/2, y = H/2}
  M.load_buttons()
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
    {label = "play", size = BUTTON_SIZE, position = get_button_position(CENTER.x, CENTER.y, BUTTON_SIZE), action = function() Screen.set("game") end},
    {label = "exit", size = BUTTON_SIZE, position = get_button_position(CENTER.x, CENTER.y + PADDING + (BUTTON_SIZE.h/2) , BUTTON_SIZE), action = function() love.event.quit() end},
  }
end

return M
