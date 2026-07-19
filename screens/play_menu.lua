Save = require("save")
Screen = require("screen")
Render = require("render")

local padding = 80
local PAD_X_RATIO, PAD_Y_RATIO = 0.7, 0.36 -- padding around the label inside the button panel, proportional to font height
local HOVER_SCALE = 1.05
local center= {x = 250, y = 250}
local screen_size = {w = 500, h = 500}
local save_data = nil

-- Rosé Pine accents
local TEXT_COLOR = {0xe0/255, 0xde/255, 0xf4/255}
local TEXT_OUTLINE = {0x39/255, 0x35/255, 0x52/255}
local HIGHLIGHT_COLOR = {0x3e/255, 0x8f/255, 0xb0/255}
local DISABLED_COLOR = {0.5, 0.5, 0.5}
local BANNER_FILL = {0x9c/255, 0xcf/255, 0xd8/255} -- foam, matches the title screen

-- Boxed-button palette (Rosé Pine).
local BTN_FILL = {0x26/255, 0x23/255, 0x3a/255} -- overlay #26233a (idle panel)
local BTN_BORDER = {0x40/255, 0x3d/255, 0x52/255} -- highlight-med (idle border)
local BTN_HOVER = {0x9c/255, 0xcf/255, 0xd8/255} -- foam (hover fill + border)
local BTN_TEXT = {0xe0/255, 0xde/255, 0xf4/255} -- light text (idle)
local BTN_TEXT_HOVER = {0x19/255, 0x17/255, 0x24/255} -- base, dark text on the foam fill

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
  Screen.set("mode_select")
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

local function draw_button(button, is_hover, this_button_size, button_position, scale)
  scale = scale or 1
  local pos = get_button_position(button_position.x, button_position.y, this_button_size)
  local w, h = this_button_size.w, this_button_size.h
  local radius = math.min(w, h) * 0.18
  local disabled = save_data == nil and button.label == "Continue From Save"
  local hot = is_hover and not disabled

  -- Subtle panel; hover emphasizes with a foam outline + foam label rather than
  -- a bright solid fill, so it sits quietly over the title art.
  love.graphics.setColor(BTN_FILL[1], BTN_FILL[2], BTN_FILL[3], hot and 0.8 or 0.4)
  love.graphics.rectangle("fill", pos.x, pos.y, w, h, radius, radius)
  love.graphics.setLineWidth(hot and 2 or 1)
  love.graphics.setColor(hot and BTN_HOVER or BTN_BORDER)
  love.graphics.rectangle("line", pos.x, pos.y, w, h, radius, radius)

  -- Centered label.
  local font = love.graphics.getFont()
  local tw = font:getWidth(button.label) * scale
  local th = font:getHeight() * scale
  local tc = disabled and DISABLED_COLOR or (hot and BTN_HOVER or BTN_TEXT)
  love.graphics.setColor(tc)
  love.graphics.print(button.label, pos.x + (w - tw) / 2, pos.y + (h - th) / 2, 0, scale, scale)
end

M.buttons = {}

function M.enter()
  save_data = Save.load_state("save_data.txt")
end

local HEADING = "HOW WILL YOU BEGIN?"
local HEADING_SCALE = 1.4
local BTN_GAP = 28 -- vertical gap between stacked buttons
local HEAD_GAP = 36 -- gap between the heading and the first button
local MENU_MARGIN = 16 -- min gap kept from the window's top/bottom edges
local BUTTON_COUNT = 3

-- Uniform button height, derived straight from the heading font (matches
-- get_button_size without needing the current graphics font to be set).
local function button_height()
  local fh = Render.font_big:getHeight()
  return fh + 2 * (fh * PAD_Y_RATIO)
end

-- Where the heading sits for a cw×ch window; `bottom` is where the buttons
-- start just beneath it. Normally anchored around 0.40*ch, but pulled up when
-- the whole heading+buttons block would overflow a short window (e.g. the
-- 800x500 minimum) so nothing gets cut off.
local function heading_layout(cw, ch)
  local h = Render.font_big:getHeight() * HEADING_SCALE
  local total = h + HEAD_GAP + BUTTON_COUNT * button_height() + (BUTTON_COUNT - 1) * BTN_GAP
  local desired_top = ch * 0.40 - h / 2
  local top = math.max(MENU_MARGIN, math.min(desired_top, ch - total - MENU_MARGIN))
  return { cy = top + h / 2, top = top, bottom = top + h }
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
        draw_button(button, true, this_button_size, button.position, HOVER_SCALE)
        this_button_size = {w = button.size.w,h= button.size.h}
      else
        draw_button(button, false, this_button_size, button.position)
      end
    else
      draw_button(button, false, this_button_size, button.position)
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

function M.load_buttons()
  local old_font = love.graphics.getFont()
  love.graphics.setFont(Render.font_big)
  -- One uniform button size for every row: width of the widest label + padding.
  local labels = { "Continue From Save", "New Game", "Back" }
  local size = { w = 0, h = 0, pad_x = 0, pad_y = 0 }
  for _, l in ipairs(labels) do
    local s = get_button_size(l)
    size.w = math.max(size.w, s.w)
    size.h, size.pad_x, size.pad_y = s.h, s.pad_x, s.pad_y
  end
  love.graphics.setFont(old_font)
  -- Stack the buttons, horizontally centered, right below the heading.
  local cw, ch = love.graphics.getDimensions()
  local step = size.h + BTN_GAP
  local continue_y = heading_layout(cw, ch).bottom + HEAD_GAP + size.h / 2
  local new_game_y = continue_y + step
  local back_y = new_game_y + step
  M.buttons = {
    {label = "Continue From Save", size = size, position = {x=center.x, y=continue_y}, action = function() load_from_save() end},
    {label = "New Game", size = size, position = {x=center.x, y=new_game_y}, action = function() start_new_game() end},
    {label = "Back", size = size, position = {x=center.x, y=back_y}, action = function() Screen.set("play") end},
  }
end

return M
