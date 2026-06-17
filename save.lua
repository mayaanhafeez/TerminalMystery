local world = require("world")

local save_template = {
  current_room = true,
  previous_room = true,
  visited = true,
  files_read = true,
  unlocked = true,
  destroyed = true,
  elapsed = true,
  rooms =true,
  command_count = true
}

local function add_world_items(state, filename)
  local rooms = {}
  for room_id in pairs(state.visited) do
    local room = world.rooms[room_id]
    rooms[room_id] = { items = {}}
    if room.mode then rooms[room_id].mode = room.mode end
    for filename, item in pairs(room.items) do
      rooms[room_id].items[filename] = {
        id = item.id,
        filename = filename,
        room = item.room,
        copied = item.copied,
        x = item.x,
        y = item.y
      }
    end
  end
  state.rooms = rooms
  return state
end

local function remove_world_items(state)
  state.rooms = nil
  return state
end

local function convert_state_to_string(state, template) --function taken from https://gist.github.com/justnom/9816256 and modified
  local state_string = "{"

  for k, v in pairs(state) do
    if not template or template[k] then
    if type(k) == "string" then
      state_string = state_string.."[\""..k.."\"]".."="
    end

    local sub_template = template and type(template[k]) == "table" and template[k] or nil
    if type(v) == "table" then
      state_string = state_string..convert_state_to_string(v, sub_template)
    elseif type(v) == "string" then
      state_string = state_string.."\""..v.."\""
    else
      state_string= state_string..tostring(v)
    end
    state_string = state_string..","
    end
  end

    if state_string ~= "" and state_string:sub(-1) == "," then
      state_string = state_string:sub(1,state_string:len()-1)
    end
  return state_string.."}"
end

local function convert_string_to_state(string)
  return load("return " .. string)()
end

local M = {}

function M.save_state(state, filename)
  local state_with_world = add_world_items(state, filename)
  local state_string = convert_state_to_string(state_with_world, save_template)
  local successs, message = love.filesystem.write(filename, state_string)
  if not successs then
    print(message)
  end
  remove_world_items(state)
end

function M.load_state(filename)
  if not love.filesystem.getInfo(filename) then
    return nil
  else
   local state_string = love.filesystem.read(filename)
    if not state_string then
      return nil
    elseif M.validate_save(state_string) then
        print(state_string)
        return convert_string_to_state(state_string)
      else
        return nil
    end
  end
end

function M.has_save(filename)
  if love.filesystem.getInfo(filename) ~= nil then
    return true
  else
    return false
  end
end

function M.delete_save(filename)
  if M.has_save(filename) then
    love.filesystem.remove(filename)
  end
end

function M.validate_save(state_string)
--checks if all state fields are valid.
  return true
end

return M
