-- test/test_screen.lua — screen.lua router behaviour

local T = require("test.runner")
local Screen = require("screen")

T.suite("register / set")

T.test("enter() is called on set()", function()
    local entered = false
    Screen.register("ts_enter", { enter = function() entered = true end })
    Screen.set("ts_enter")
    T.ok(entered)
end)

T.test("screen without enter() does not error on set()", function()
    Screen.register("ts_no_enter", {})
    Screen.set("ts_no_enter")
    T.ok(true)
end)

T.test("enter() is called again each time set() is called", function()
    local count = 0
    Screen.register("ts_reenter", { enter = function() count = count + 1 end })
    Screen.set("ts_reenter")
    Screen.set("ts_reenter")
    T.eq(count, 2)
end)

T.suite("keypressed routing")

T.test("keypressed is forwarded to current screen", function()
    local received = nil
    Screen.register("ts_kp", { keypressed = function(k) received = k end })
    Screen.set("ts_kp")
    Screen.keypressed("x")
    T.eq(received, "x")
end)

T.test("screen without keypressed does not error", function()
    Screen.register("ts_kp_none", {})
    Screen.set("ts_kp_none")
    Screen.keypressed("enter")
    T.ok(true)
end)

T.test("switching screens changes keypressed target", function()
    local a_got, b_got = nil, nil
    Screen.register("ts_sw1", { keypressed = function(k) a_got = k end })
    Screen.register("ts_sw2", { keypressed = function(k) b_got = k end })
    Screen.set("ts_sw1")
    Screen.keypressed("a")
    Screen.set("ts_sw2")
    Screen.keypressed("b")
    T.eq(a_got, "a")
    T.eq(b_got, "b")
    T.nil_(a_got == "b" and a_got or nil, "a screen should not receive b")
end)

T.suite("other callback routing")

T.test("update is forwarded with dt", function()
    local got_dt = nil
    Screen.register("ts_update", { update = function(dt) got_dt = dt end })
    Screen.set("ts_update")
    Screen.update(0.016)
    T.eq(got_dt, 0.016)
end)

T.test("mousepressed is forwarded with x, y, button", function()
    local gx, gy, gb = nil, nil, nil
    Screen.register("ts_mp", { mousepressed = function(x, y, b) gx, gy, gb = x, y, b end })
    Screen.set("ts_mp")
    Screen.mousepressed(100, 200, 1)
    T.eq(gx, 100)
    T.eq(gy, 200)
    T.eq(gb, 1)
end)

T.test("text_input is forwarded", function()
    local got = nil
    Screen.register("ts_ti", { text_input = function(t) got = t end })
    Screen.set("ts_ti")
    Screen.text_input("z")
    T.eq(got, "z")
end)

T.test("screen without update does not error", function()
    Screen.register("ts_no_update", {})
    Screen.set("ts_no_update")
    Screen.update(0.1)
    T.ok(true)
end)
