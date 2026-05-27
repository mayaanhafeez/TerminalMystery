-- test/runner.lua — minimal test harness, no dependencies

local M = {}
local passed, failed = 0, 0
local current_suite = ""

function M.suite(name)
    current_suite = name
    print("\n" .. name)
end

function M.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write("  \27[32m✓\27[0m " .. name .. "\n")
    else
        failed = failed + 1
        io.write("  \27[31m✗\27[0m " .. name .. "\n")
        io.write("    " .. tostring(err):gsub("\n", "\n    ") .. "\n")
    end
end

function M.eq(actual, expected, label)
    if actual ~= expected then
        error(
            (label and label .. "\n  " or "") ..
            "expected: " .. tostring(expected) .. "\n" ..
            "  actual: " .. tostring(actual), 2
        )
    end
end

function M.ok(val, label)
    if not val then
        error((label or "expected truthy, got " .. tostring(val)), 2)
    end
end

function M.nil_(val, label)
    if val ~= nil then
        error((label or "expected nil, got " .. tostring(val)), 2)
    end
end

-- Check that `list` contains `value`.
function M.has(list, value, label)
    for _, v in ipairs(list) do
        if v == value then return end
    end
    local items = {}
    for _, v in ipairs(list) do table.insert(items, tostring(v)) end
    error(
        (label or "list does not contain expected value") .. "\n" ..
        "  looking for: " .. tostring(value) .. "\n" ..
        "  list: {" .. table.concat(items, ", ") .. "}", 2
    )
end

-- Check that `list` does NOT contain `value`.
function M.not_has(list, value, label)
    for _, v in ipairs(list) do
        if v == value then
            error((label or "list should not contain " .. tostring(value)), 2)
        end
    end
end

function M.summary()
    print(string.format("\n%d passed, %d failed", passed, failed))
    if failed > 0 then os.exit(1) end
end

return M
