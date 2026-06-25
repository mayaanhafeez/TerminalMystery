Screen = require("screen")
Render = require("render")
Save = require("save")
World = require("world")

local aspect_ratio = 0.2
local padding = 80
local center= {x = 250, y = 250}
local screen_size = {w = 500, h = 500}
local button_size = {w = ((24/9)*screen_size.w)*aspect_ratio, h = screen_size.h*aspect_ratio}

local M = {}
local function exit()
  love.event.quit()
end

local function get_button_size()
  return button_size
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
    local button_position = get_button_position(my_button.position.x, my_button.position.y, this_button_size)
    if x > button_position.x and x< (button_position.x + this_button_size.w) and y > button_position.y and y<(button_position.y + this_button_size.h) then
      return my_button
    end
  end
  return nil
end

local function draw_button(button, color, this_button_size, button_position)
  button_position = get_button_position(button_position.x, button_position.y, this_button_size)
  local color1 = color[1]
  local color2 = color[2]
  local color3 = color[3]
  love.graphics.setColor(color1,color2,color3)
  love.graphics.rectangle("fill", button_position.x, button_position.y, this_button_size.w, this_button_size.h, 5)
  local label = button.label
  local font = love.graphics.getFont()
  local text_position = {x = button_position.x + (this_button_size.w - font:getWidth(label)) /2, y= button_position.y + (this_button_size.h - font:getHeight()) /2}
  love.graphics.setColor(0,0,0)
  love.graphics.print(label, text_position.x, text_position.y)
end

M.buttons = {}

function M.draw()
  --get screen middle
  local cw,ch = love.graphics.getDimensions()
  if screen_size.w~=cw or screen_size.h~=ch then
    screen_size.w, screen_size.h = cw,ch
    center = {x = screen_size.w/2, y = screen_size.h/2}
    M.load_buttons()
  end
  love.graphics.clear(0,0,0,1)
  local title = "Terminal Mystery"
  local title_font = love.graphics.newFont(32)
  local old_font = love.graphics.getFont()
  love.graphics.setFont(title_font)
  local text_position = {x = center.x - title_font:getWidth(title) /2, y= (center.y - 200) - title_font:getHeight() /2}
  love.graphics.setColor(1,1,1)
  love.graphics.print("Terminal Mystery", text_position.x, text_position.y)
  love.graphics.setFont(old_font)
  for _, button in ipairs(M.buttons) do
    local this_button_size = {w = button.size.w,h= button.size.h}
    if (button_selected()) then
      if (button.label == button_selected().label) then
        this_button_size = {w =this_button_size.w * 1.03, h =this_button_size.h *1.03}
        draw_button(button,{0.67,0.67,0.67},this_button_size, button.position)
        this_button_size = {w = button.size.w,h= button.size.h}
      else
        draw_button(button, {1,1,1}, this_button_size, button.position)
      end
    else
      draw_button(button, {1,1,1}, this_button_size, button.position)
    end
  end
end

local function get_button_index(button)
  M.load_buttons()
  for i,k in ipairs(M.buttons) do
    if k.label == button.label then
      return i
    end
  end
end

function M.keypressed(key)
  M.load_buttons()
  local current_button = button_selected()
  if current_button == nil then
    if key == "down" or key == "up" then
      love.mouse.setPosition(M.buttons[1].position.x, M.buttons[1].position.y)
    end
  else
    local index = get_button_index(current_button)
    if key == "down" then
      index = index + 1
    elseif key == "up" then
      index = index - 1
    end
    if index >= 1 and index <= #M.buttons then
      love.mouse.setPosition(M.buttons[index].position.x, M.buttons[index].position.y)
    end
    end
  if key == "return" and current_button then
    current_button.action()
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
    {label = "play", size = get_button_size(), position = {x=center.x, y=center.y}, action = function() Screen.set("play_menu") end},
    {label = "exit", size = get_button_size(), position = {x=center.x, y=center.y + padding + (button_size.h/2)}, action = function() exit() end},
  }
end

return M
