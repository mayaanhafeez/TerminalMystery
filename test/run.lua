-- test/run.lua — entry point: lua test/run.lua (run from project root)

-- Ensure project root is on the module path
local root = arg[0]:match("^(.*)/test/run%.lua$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

require("test.test_world")
require("test.test_completion")
require("test.test_navigation")
require("test.test_items")
require("test.test_evidence")
require("test.test_screen")
require("test.test_save")
require("test.test_solve")
-- Last: it stubs the GameScreen global that vim.lua's :q hands off to.
require("test.test_vim")

local T = require("test.runner")
T.summary()
