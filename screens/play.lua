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

local function draw_button_border(x, y, w, h)
	local B = 11
	local u = 2 -- pixel unit for outlines / bevel
	local edge = { 0.10, 0.08, 0.06 }
	local body = { 0.42, 0.30, 0.18 }
	local hi = { 0.64, 0.48, 0.28 }
	local sh = { 0.24, 0.16, 0.09 }

	-- body bands framing the opening (top / bottom / left / right)
	love.graphics.setColor(body)
	love.graphics.rectangle("fill", x, y, w, B)
	love.graphics.rectangle("fill", x, y + h - B, w, B)
	love.graphics.rectangle("fill", x, y, B, h)
	love.graphics.rectangle("fill", x + w - B, y, B, h)

	-- outer dark outline
	love.graphics.setColor(edge)
	love.graphics.rectangle("fill", x, y, w, u)
	love.graphics.rectangle("fill", x, y + h - u, w, u)
	love.graphics.rectangle("fill", x, y, u, h)
	love.graphics.rectangle("fill", x + w - u, y, u, h)

	-- bevel: highlight along top + left, shadow along bottom + right
	love.graphics.setColor(hi)
	love.graphics.rectangle("fill", x + u, y + u, w - 2 * u, u)
	love.graphics.rectangle("fill", x + u, y + u, u, h - 2 * u)
	love.graphics.setColor(sh)
	love.graphics.rectangle("fill", x + u, y + h - 2 * u, w - 2 * u, u)
	love.graphics.rectangle("fill", x + w - 2 * u, y + u, u, h - 2 * u)

	-- inner dark outline around the opening
	love.graphics.setColor(edge)
	local ix, iy, iw, ih = x + B - u, y + B - u, w - 2 * (B - u), h - 2 * (B - u)
	love.graphics.rectangle("fill", ix, iy, iw, u)
	love.graphics.rectangle("fill", ix, iy + ih - u, iw, u)
	love.graphics.rectangle("fill", ix, iy, u, ih)
	love.graphics.rectangle("fill", ix + iw - u, iy, u, ih)

	-- corner studs
	local s = 5
	love.graphics.setColor(hi)
	for _, c in ipairs({ { x + u + 1, y + u + 1 }, { x + w - u - 1 - s, y + u + 1 },
		{ x + u + 1, y + h - u - 1 - s }, { x + w - u - 1 - s, y + h - u - 1 - s } }) do
		love.graphics.rectangle("fill", c[1], c[2], s, s)
		love.graphics.setColor(edge)
		love.graphics.rectangle("fill", c[1] + s - 1, c[2] + s - 1, 1, 1)
		love.graphics.setColor(hi)
	end
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
  love.graphics.rectangle("fill", button_position.x, button_position.y, this_button_size.w, this_button_size.h)
  local label = button.label
  local font = love.graphics.getFont()
  local text_position = {x = button_position.x + (this_button_size.w - font:getWidth(label)) /2, y= button_position.y + (this_button_size.h - font:getHeight()) /2}
  love.graphics.setColor(43/255,36/255,25/255)
  love.graphics.print(label, text_position.x, text_position.y)
  draw_button_border(button_position.x, button_position.y, this_button_size.w, this_button_size.h)
end

M.buttons = {}

function M.draw()
  --get screen middle
  local button_color = {0.91, 0.87, 0.78}
  local hover_color = {221/255, 208/255, 180/255}
  local cw,ch = love.graphics.getDimensions()
  if screen_size.w~=cw or screen_size.h~=ch then
    screen_size.w, screen_size.h = cw,ch
    center = {x = screen_size.w/2, y = screen_size.h/2}
    M.load_buttons()
  end
  love.graphics.clear(0,0,0,1)
  local img = love.graphics.newImage("assets/sprites/floor/foyer.png")
  img:setWrap("repeat", "repeat")
  local iw, ih = img:getDimensions()
  local quad = love.graphics.newQuad(0,0, cw, ch, iw, ih)
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(img, quad, 0,0)
  local title = "Terminal Mystery"
  local old_font = love.graphics.getFont()
  love.graphics.setFont(Render.font_handwriting_large)
  local title_font = love.graphics.getFont()
  local text_position = {x = center.x - title_font:getWidth(title) /2, y= (center.y - 200) - title_font:getHeight() /2}
  love.graphics.setColor(1,1,1)
  love.graphics.print("Terminal Mystery", text_position.x, text_position.y)
  love.graphics.setFont(old_font)
  for _, button in ipairs(M.buttons) do
    local this_button_size = {w = button.size.w,h= button.size.h}
    if (button_selected()) then
      if (button.label == button_selected().label) then
        this_button_size = {w =this_button_size.w * 1.03, h =this_button_size.h *1.03}
        draw_button(button,hover_color,this_button_size, button.position)
        this_button_size = {w = button.size.w,h= button.size.h}
      else

        draw_button(button, button_color, this_button_size, button.position)
      end
    else
      draw_button(button, button_color, this_button_size, button.position)
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
  M.buttons = {
    {label = "Play", size = get_button_size(), position = {x=center.x, y=center.y}, action = function() Screen.set("play_menu") end},
    {label = "Exit", size = get_button_size(), position = {x=center.x, y=center.y + padding + (button_size.h/2)}, action = function() exit() end},
  }
end

return M
