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
require("test.test_audio")
-- test_meta stubs GameScreen/Save for `exit`; test_vim overwrites the same
-- GameScreen global with its own stub and must stay last.
require("test.test_meta")
require("test.test_vim")

local T = require("test.runner")
T.summary()
