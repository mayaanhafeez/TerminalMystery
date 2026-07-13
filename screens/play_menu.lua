Save = require("save")
Screen = require("screen")
Render = require("render")

local padding = 80
local PAD_X_RATIO, PAD_Y_RATIO = 0.35, 0.12 -- hitbox padding around the text, proportional to font height
local HOVER_SCALE = 1.18
local center= {x = 250, y = 250}
local screen_size = {w = 500, h = 500}
local save_data = nil

-- Rosé Pine accents
local TEXT_COLOR = {0xe0/255, 0xde/255, 0xf4/255}
local TEXT_OUTLINE = {0x39/255, 0x35/255, 0x52/255}
local HIGHLIGHT_COLOR = {0x3e/255, 0x8f/255, 0xb0/255}
local DISABLED_COLOR = {0.5, 0.5, 0.5}
local BANNER_FILL = {0x9c/255, 0xcf/255, 0xd8/255} -- foam, matches the title screen

local function get_button_size(label)
  local font = love.graphics.getFont()
  local pad_x = font:getHeight() * PAD_X_RATIO
  local pad_y = font:getHeight() * PAD_Y_RATIO
  return {w = font:getWidth(label) + pad_x * 2, h = font:getHeight() + pad_y * 2, pad_x = pad_x, pad_y = pad_y}
end

local M = {}

local function load_from_save()
  save_data = Save.load_state("save_data.txt")
  if save_data then
    GameScreen.start_from_save(save_data)
    Screen.set("game")
  end
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
    local button_position = get_button_position(my_button.position.x, my_button.position.y, this_button_size)
    if x > button_position.x and x< (button_position.x + this_button_size.w) and y > button_position.y and y<(button_position.y + this_button_size.h) then
      return my_button
    end
  end
  return nil
end

-- Draws text with a solid 1px outline behind the fill color.
local function print_outlined(text, x, y, fill_color, scale)
  scale = scale or 1
  local o = scale
  love.graphics.setColor(TEXT_OUTLINE[1], TEXT_OUTLINE[2], TEXT_OUTLINE[3], 1)
  for _, d in ipairs({ {-o,0},{o,0},{0,-o},{0,o},{-o,-o},{o,-o},{-o,o},{o,o} }) do
    love.graphics.print(text, x + d[1], y + d[2], 0, scale, scale)
  end
  love.graphics.setColor(fill_color[1], fill_color[2], fill_color[3], 1)
  love.graphics.print(text, x, y, 0, scale, scale)
end

local function draw_button(button, color, this_button_size, button_position, scale)
  scale = scale or 1
  button_position = get_button_position(button_position.x, button_position.y, this_button_size)
  local tx = button_position.x + button.size.pad_x * scale
  local ty = button_position.y + button.size.pad_y * scale
  local disabled = save_data == nil and button.label == "Continue From Save"
  print_outlined(button.label, tx, ty, disabled and DISABLED_COLOR or color, scale)
end

M.buttons = {}

function M.enter()
  save_data = Save.load_state("save_data.txt")
end

local HEADING = "HOW WILL YOU BEGIN?"
local HEADING_SCALE = 1.4

-- Where the heading sits for a cw×ch window; `bottom` is where the buttons
-- start just beneath it.
local function heading_layout(cw, ch)
  local h = Render.font_big:getHeight() * HEADING_SCALE
  local cy = ch * 0.40
  return { cy = cy, top = cy - h / 2, bottom = cy + h / 2 }
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
  Render.draw_menu_background(cw, ch, true)
  local old_font = love.graphics.getFont()
  -- Heading that frames the New Game / Continue choice, with the buttons right
  -- beneath it.
  local hl = heading_layout(cw, ch)
  love.graphics.setFont(Render.font_big)
  local hx = center.x - (Render.font_big:getWidth(HEADING) * HEADING_SCALE) / 2
  print_outlined(HEADING, hx, hl.top, BANNER_FILL, HEADING_SCALE)

  love.graphics.setFont(Render.font_big)
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

function M.mousepressed(_, _, mouse_button)
  local button = button_selected()
  if button ~= nil and mouse_button == 1 then
    button.action()
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
  if key == "1" then
    love.mouse.setPosition(M.buttons[1].position.x, M.buttons[1].position.y)
  elseif key == "2" then
      love.mouse.setPosition(M.buttons[2].position.x, M.buttons[2].position.y)
  elseif key == "3" then
      love.mouse.setPosition(M.buttons[3].position.x, M.buttons[3].position.y)
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
  if key == "escape" then
    M.buttons[3].action()
  end
end

local BTN_GAP = 28 -- vertical gap between stacked buttons

function M.load_buttons()
  local old_font = love.graphics.getFont()
  love.graphics.setFont(Render.font_big)
  local continue_size = get_button_size("Continue From Save")
  local new_game_size = get_button_size("New Game")
  local back_size = get_button_size("Back")
  love.graphics.setFont(old_font)
  -- Stack the buttons, horizontally centered, right below the heading.
  local cw, ch = love.graphics.getDimensions()
  local start_y = heading_layout(cw, ch).bottom + 36
  local continue_y = start_y + continue_size.h / 2
  local new_game_y = continue_y + continue_size.h / 2 + BTN_GAP + new_game_size.h / 2
  local back_y = new_game_y + new_game_size.h / 2 + BTN_GAP + back_size.h / 2
  M.buttons = {
    {label = "Continue From Save", size = continue_size, position = {x=center.x, y=continue_y}, action = function() load_from_save() end},
    {label = "New Game", size = new_game_size, position = {x=center.x, y=new_game_y}, action = function() start_new_game() end},
    {label = "Back", size = back_size, position = {x=center.x, y=back_y}, action = function() Screen.set("play") end},
  }
end

return M
