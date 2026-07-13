Screen = require("screen")
Render = require("render")
Save = require("save")
World = require("world")

local padding = 80
local PAD_X_RATIO, PAD_Y_RATIO = 0.35, 0.12 -- hitbox padding around the text, proportional to font height
local HOVER_SCALE = 1.18
local center= {x = 250, y = 250}
local screen_size = {w = 500, h = 500}

local TITLE_SCALE = 2.2 -- title always renders bigger than any button state

-- Rosé Pine accents
local TEXT_COLOR = {0xe0/255, 0xde/255, 0xf4/255}
local TEXT_OUTLINE = {0x39/255, 0x35/255, 0x52/255}
local HIGHLIGHT_COLOR = {0x3e/255, 0x8f/255, 0xb0/255}

local M = {}
local function exit()
  love.event.quit()
end

local function get_button_size(label)
  local font = love.graphics.getFont()
  local pad_x = font:getHeight() * PAD_X_RATIO
  local pad_y = font:getHeight() * PAD_Y_RATIO
  return {w = font:getWidth(label) + pad_x * 2, h = font:getHeight() + pad_y * 2, pad_x = pad_x, pad_y = pad_y}
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

-- Draws text with a solid 1px outline behind the fill color. `bold` layers a
-- couple of 1px-offset fill passes on top to thicken the strokes — a faux
-- bold, since none of the bundled fonts ship a bold weight.
local function print_outlined(text, x, y, fill_color, scale, bold)
  scale = scale or 1
  local o = scale
  love.graphics.setColor(TEXT_OUTLINE[1], TEXT_OUTLINE[2], TEXT_OUTLINE[3], 1)
  for _, d in ipairs({ {-o,0},{o,0},{0,-o},{0,o},{-o,-o},{o,-o},{-o,o},{o,o} }) do
    love.graphics.print(text, x + d[1], y + d[2], 0, scale, scale)
  end
  love.graphics.setColor(fill_color[1], fill_color[2], fill_color[3], 1)
  if bold then
    for _, d in ipairs({ {0,0},{scale,0},{0,scale},{scale,scale} }) do
      love.graphics.print(text, x + d[1], y + d[2], 0, scale, scale)
    end
  else
    love.graphics.print(text, x, y, 0, scale, scale)
  end
end

local function draw_button(button, color, this_button_size, button_position, scale)
  scale = scale or 1
  button_position = get_button_position(button_position.x, button_position.y, this_button_size)
  local tx = button_position.x + button.size.pad_x * scale
  local ty = button_position.y + button.size.pad_y * scale
  print_outlined(button.label, tx, ty, color, scale)
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
  Render.draw_menu_background(cw, ch, false)
  local title = "Terminal Mystery"
  local old_font = love.graphics.getFont()
  love.graphics.setFont(Render.font_big)
  local title_font = love.graphics.getFont()
  local tx = center.x - (title_font:getWidth(title) * TITLE_SCALE) / 2
  local ty = (center.y - 200) - (title_font:getHeight() * TITLE_SCALE) / 2
  print_outlined(title, tx, ty, TEXT_COLOR, TITLE_SCALE, true)

  for _, button in ipairs(M.buttons) do
    local this_button_size = {w = button.size.w,h= button.size.h}
    if (button_selected()) then
      if (button.label == button_selected().label) then
        this_button_size = {w =this_button_size.w * HOVER_SCALE, h =this_button_size.h *HOVER_SCALE}
        draw_button(button, HIGHLIGHT_COLOR, this_button_size, button.position, HOVER_SCALE)
        this_button_size = {w = button.size.w,h= button.size.h}
      else

        draw_button(button, TEXT_COLOR, this_button_size, button.position)
      end
    else
      draw_button(button, TEXT_COLOR, this_button_size, button.position)
    end
  end
  love.graphics.setFont(old_font)
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
  if key == "1" then
    love.mouse.setPosition(M.buttons[1].position.x, M.buttons[1].position.y)
  elseif key == "2" then
    love.mouse.setPosition(M.buttons[2].position.x, M.buttons[2].position.y)
  end
  local current_button = button_selected()
  if current_button == nil then
    if key == "down" or key == "up" or key == "j" or key == "k" then
      love.mouse.setPosition(M.buttons[1].position.x, M.buttons[1].position.y)
    end
  else
    local index = get_button_index(current_button)
    if key == "down" or key == "j" then
      index = index + 1
    elseif key == "up" or key == "k" then
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
  local old_font = love.graphics.getFont()
  love.graphics.setFont(Render.font_big)
  local play_size = get_button_size("Play")
  local exit_size = get_button_size("Exit")
  love.graphics.setFont(old_font)
  M.buttons = {
    {label = "Play", size = play_size, position = {x=padding + play_size.w/2, y=center.y}, action = function() Screen.set("play_menu") end},
    {label = "Exit", size = exit_size, position = {x=padding + exit_size.w/2, y=center.y + padding + (exit_size.h/2)}, action = function() exit() end},
  }
end

return M
