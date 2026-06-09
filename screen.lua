local screens = {}
local current = nil

local M = {}

function M.register(name, module)
  screens[name] = module
end

function M.set(name)
  current = screens[name]
  if current.enter then
    current.enter()
  end
end

function M.update(dt)
  if current.update then current.update(dt) end
end

function M.draw()
  if current.draw then current.draw() end
end

function M.text_input(t)
  if current.text_input then current.text_input(t) end
end

function M.mousepressed(x, y, button)
  if current.mousepressed then current.mousepressed(x, y, button) end
end

function M.keypressed(key)
  if current.keypressed then current.keypressed(key) end
end

return M
