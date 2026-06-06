local function should_save(string)
  local saveable_fields = {} -- needs to include subfields as well
  for _ ,v in ipairs(saveable_fields) do
    if string == v then
    return true
    end
  end
    return false
  end

local function convert_state_to_string(state) --function taken from https://gist.github.com/justnom/9816256 and modified
  local state_string = "{"

  for k, v in pairs(state) do
    if type(k) == "string" then
      state_string = state_string.."[\""..k.."\"]".."="
    end

    if type(v) == "table" then
      state_string = state_string..convert_state_to_string(v)
    elseif type(v) == "boolean" then
      state_string = state_string..tostring(v)
    else
      state_string = state_string..","
    end
  end

    if state_string ~= "" then
      state_string = state_string:sub(1,state_string:len()-1)
    end
  return state_string.."}"
end

local function convert_string_to_state(string)
  local state = {}
  for str in string.gmatch(string, "([^".."%s".."]+)") do
    state.insert(state, str)
  end
  return state
end

local M = {}

function M.save_state(state, filename)
--saves state: current_room, previous_room, visited, files_read, unlocked, elapsed, command_count
--writes them to a text file
  local state_string = convert_state_to_string(state)
  local successs, message = love.filesystem.write(filename, state_string)
  if not successs then
    print(message)
  end
end

function M.load_state(filename)
--reads file extracts state, validates state. returns nil on failed validation or other error.
--returns state
  if not love.filesystem.getInfo(filename) then
    return nil
  else
   local state_string = love.filesystem.read(filename)
    if not state_string then
      return nil
    elseif M.validate_save(state_string) then
        return convert_string_to_state(state_string)
      else
        return nil
    end
  end
end

function M.has_save(filename)
--checks if save file exists
  if love.filesystem.getInfo(filename) ~= nil then
    return true
  else
    return false
  end
end

function M.delete_save(filename)
--if save file exists delete it.
  if M.has_save(filename) then
    love.filesystem.remove(filename)
  end
end

function M.validate_save(state_string)
--checks if all state fields are valid.
  return true
end

return M
