-- commands/init.lua
-- Entry point. Merges all handler groups and exposes M.execute.

local World      = require("world")
local Navigation = require("commands.navigation")
local Evidence   = require("commands.evidence")
local Items      = require("commands.items")
local Meta       = require("commands.meta")

local M = {}

local function tokenize(input)
    local tokens = {}
    local i = 1
    local n = #input
    while i <= n do
        while i <= n and input:sub(i, i):match("%s") do
            i = i + 1
        end
        if i > n then break end
        local c = input:sub(i, i)
        if c == '"' or c == "'" then
            local quote = c
            i = i + 1
            local start = i
            while i <= n and input:sub(i, i) ~= quote do
                i = i + 1
            end
            table.insert(tokens, input:sub(start, i - 1))
            i = i + 1
        else
            local start = i
            while i <= n and not input:sub(i, i):match("%s") do
                i = i + 1
            end
            table.insert(tokens, input:sub(start, i - 1))
        end
    end
    return tokens
end

local function locked_message(cmd)
    if cmd == "cat" then
        return "Your hand hovers over the evidence — but you stay it.\n"
            .. "Walk the mansion first. Do not disturb anything until you\n"
            .. "have at least taken the measure of the place."
    elseif cmd == "grep" then
        return "You have nothing yet to cross-reference.\n"
            .. "Read at least two pieces of evidence before you try to\n"
            .. "draw lines between them."
    end
    return "That ability is not yet available to you."
end

local handlers = {}
for k, v in pairs(Navigation) do handlers[k] = v end
for k, v in pairs(Evidence)   do handlers[k] = v end
for k, v in pairs(Items)      do handlers[k] = v end
for k, v in pairs(Meta)       do handlers[k] = v end

function M.execute(state, input)
    input = input:gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return "" end

    if state.start_time == nil then
        state.start_time = love.timer.getTime()
    end

    local tokens = tokenize(input)
    local cmd = tokens[1]:lower()
    local args = {}
    for i = 2, #tokens do args[i - 1] = tokens[i] end

    -- `exit` is meta (quit/save prompt), not an investigative move, so it
    -- doesn't count toward the command score.
    if cmd ~= "exit" then
        state.command_count = state.command_count + 1
    end

    local handler = handlers[cmd]
    if not handler then
        return "You mutter the word \"" .. cmd .. "\" under your breath.\n"
            .. "Nothing in the house responds. (Type `help` for what you\n"
            .. "can actually do.)"
    end

    if not state.unlocked[cmd] then
        return locked_message(cmd)
    end

    return handler(state, args) or ""
end

return M
