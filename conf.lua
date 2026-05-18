function love.conf(t)
    t.identity = "terminal_mystery"
    t.version  = "11.4"
    t.window.title     = "Terminal Mystery"
    t.window.width     = 1280
    t.window.height    = 800
    t.window.resizable = false
    t.window.vsync     = 1
    t.console          = false
    -- We don't use these modules; trim them so the love runtime stays light.
    t.modules.joystick = false
    t.modules.physics  = false
    t.modules.video    = false
end
