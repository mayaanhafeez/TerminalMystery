Screen = require("screen")
Render = require("render")

local backgroundImage
local function button_selected(mouse_position)
  -- returns what button the mouse is over currently
end

M = {}

M.buttons = {
  {label = "play", action = function() Screen.set("game") end},
  {label = "exit", action = function() love.event.quit() end},
}
function M.draw()
  --stuff to draw innit
  backgroundImage = love.graphics.newImage("/assets/kenney_tiny-dungeon/Tiles/tile_0000.png")
  love.graphics.draw(backgroundImage, 0, 0 ,0, 16,16)
  love.graphics.rectangle("line", 100, 50, 200, 150)

end

function M.mousepressed(x, y, button)
  if button == 1 and button_selected(love.mouse.getPosition) then
    print("button 1 pressed")
  end
end

return M
