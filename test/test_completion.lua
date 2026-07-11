-- test/test_completion.lua — tab completion, including ../path cases

local T = require("test.runner")
local World = require("world")
local Completion = require("commands.completion")

-- State helpers
local function make_state(current, visited_list)
    local s = World.new_state()
    s.current_room = current or "foyer"
    s.visited = {}
    for _, id in ipairs(visited_list or { current or "foyer" }) do
        s.visited[id] = true
    end
    return s
end

-- Collect just the raw completion strings for a given input
local function completions(state, input)
    return Completion.get_completions(state, input)
end

-- -----------------------------------------------------------------------
T.suite("Command name completion")

T.test("empty input returns all commands", function()
    local state = make_state("foyer")
    local c = completions(state, "")
    T.has(c, "cd ")
    T.has(c, "ls ")
    T.has(c, "cat ")
    T.has(c, "mv ")
    T.has(c, "sed ")
end)

T.test("partial command narrows list", function()
    local state = make_state("foyer")
    local c = completions(state, "c")
    T.has(c, "cat ")
    T.has(c, "cd ")
    T.has(c, "cp ")
    T.has(c, "chmod ")
    T.not_has(c, "ls ")
end)

-- -----------------------------------------------------------------------
T.suite("cd / ls — direct exit completion")

T.test("cd <space> suggests adjacent rooms", function()
    local state = make_state("foyer")
    local c = completions(state, "cd ")
    T.has(c, "cd The Den/")
    T.has(c, "cd Sunroom/")
    T.has(c, "cd Garage/")
    T.has(c, "cd Game Room/")
end)

T.test("cd partial filters by prefix", function()
    local state = make_state("foyer")
    local c = completions(state, "cd S")
    T.has(c, "cd Sunroom/")
    T.has(c, "cd Server Room/")
    T.not_has(c, "cd The Den/")
end)

T.test("cd does not suggest hidden rooms", function()
    local state = make_state("den", {"den", "foyer"})
    local c = completions(state, "cd ")
    for _, v in ipairs(c) do
        T.ok(not v:find("closet"), "hidden .closet should not appear: " .. v)
    end
end)

-- -----------------------------------------------------------------------
T.suite("cd / ls — path completion with ../")

T.test("cd .. offers ../ continuation", function()
    local state = make_state("home_office")
    local c = completions(state, "cd ..")
    T.has(c, "cd ../")
end)

T.test("cd . offers ../ continuation", function()
    local state = make_state("home_office")
    local c = completions(state, "cd .")
    T.has(c, "cd ../")
end)

T.test("cd ../ from home_office shows foyer's exits", function()
    local state = make_state("home_office")
    local c = completions(state, "cd ../")
    T.has(c, "cd ../The Den/")
    T.has(c, "cd ../Sunroom/")
    T.has(c, "cd ../Garage/")
end)

T.test("cd ../S from home_office filters to S-prefixed rooms", function()
    local state = make_state("home_office")
    local c = completions(state, "cd ../S")
    T.has(c, "cd ../Sunroom/")
    T.has(c, "cd ../Server Room/")
    T.not_has(c, "cd ../The Den/")
end)

T.test("cd ../ from sunroom shows the shared foyer exits", function()
    local state = make_state("sunroom")
    local c = completions(state, "cd ../")
    T.has(c, "cd ../The Den/")
    T.has(c, "cd ../Garage/")
end)

T.test("ls ../ from den shows foyer's exits", function()
    local state = make_state("den")
    local c = completions(state, "ls ../")
    T.has(c, "ls ../Sunroom/")
    T.has(c, "ls ../Garage/")
end)

-- -----------------------------------------------------------------------
T.suite("mv / cp — destination room completion")

T.test("mv dst suggests visited rooms", function()
    local state = make_state("sunroom", {"sunroom", "foyer", "cellar"})
    local c = completions(state, "mv espresso_bar.txt ")
    T.has(c, "mv espresso_bar.txt Wine Cellar ")
    T.has(c, "mv espresso_bar.txt Entrance Hall ")
    T.not_has(c, "mv espresso_bar.txt Home Office ")  -- not visited
end)

T.test("mv dst offers ./ shorthand", function()
    local state = make_state("sunroom", {"sunroom"})
    local c = completions(state, "mv espresso_bar.txt ")
    T.has(c, "mv espresso_bar.txt ./ ")
end)

T.test("mv dst .. offers ../ continuation", function()
    local state = make_state("sunroom", {"sunroom", "foyer", "cellar"})
    local c = completions(state, "mv espresso_bar.txt ..")
    T.has(c, "mv espresso_bar.txt ../")
end)

T.test("mv dst ../ shows visited rooms under parent", function()
    local state = make_state("sunroom", {"sunroom", "foyer", "cellar", "home_office"})
    local c = completions(state, "mv espresso_bar.txt ../")
    T.has(c, "mv espresso_bar.txt ../Wine Cellar ")
    T.has(c, "mv espresso_bar.txt ../Home Office ")
    T.not_has(c, "mv espresso_bar.txt ../Den ")  -- not visited
end)

T.test("mv dst ../W filters to visited W-prefixed rooms", function()
    local state = make_state("home_office", {"home_office", "foyer", "cellar", "sunroom"})
    local c = completions(state, "mv draft_email.txt ../W")
    T.has(c, "mv draft_email.txt ../Wine Cellar ")
    T.not_has(c, "mv draft_email.txt ../Sunroom ")
end)

T.test("cp dst ../ works the same as mv", function()
    local state = make_state("home_office", {"home_office", "foyer", "cellar"})
    local c = completions(state, "cp draft_email.txt ../")
    T.has(c, "cp draft_email.txt ../Wine Cellar ")
end)

-- -----------------------------------------------------------------------
T.suite("cat / rm — file completion")

T.test("cat suggests current room files", function()
    local state = make_state("home_office")
    local c = completions(state, "cat ")
    T.has(c, "cat draft_email.txt ")
    T.has(c, "cat repo_log.txt ")
end)

T.test("cat partial filters files", function()
    local state = make_state("home_office")
    local c = completions(state, "cat d")
    T.has(c, "cat draft_email.txt ")
    T.not_has(c, "cat repo_log.txt ")
end)

T.test("cat does not suggest hidden files", function()
    local state = make_state("home_office")
    local c = completions(state, "cat ")
    T.not_has(c, "cat cipher_note.txt ")
end)

T.test("rm suggests current room files", function()
    local state = make_state("cellar")
    local c = completions(state, "rm ")
    T.has(c, "rm badge.txt ")
    T.has(c, "rm cellar_access_log.txt ")
end)

-- -----------------------------------------------------------------------
T.suite("accuse completion")

T.test("accuse with no partial lists all suspects", function()
    local state = make_state("foyer")
    local c = completions(state, "accuse ")
    T.has(c, "accuse Daniel Lin")
    T.has(c, "accuse Ayesha Raza")
end)

T.test("accuse partial filters suspects", function()
    local state = make_state("foyer")
    local c = completions(state, "accuse D")
    T.has(c, "accuse Daniel Lin")
    T.not_has(c, "accuse Ayesha Raza")
end)

-- -----------------------------------------------------------------------
T.suite("grep — file completion skips pattern slot")

T.test("grep with no pattern returns nothing", function()
    local state = make_state("home_office")
    local c = completions(state, "grep ")
    T.eq(#c, 0)
end)

T.test("grep with pattern typed suggests files", function()
    local state = make_state("home_office")
    local c = completions(state, "grep foxglove ")
    T.has(c, "grep foxglove draft_email.txt ")
end)
