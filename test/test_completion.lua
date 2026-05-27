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
    T.has(c, "cd Library ")
    T.has(c, "cd Cellar ")
    T.has(c, "cd Study ")
    T.has(c, "cd Conservatory ")
end)

T.test("cd partial filters by prefix", function()
    local state = make_state("foyer")
    local c = completions(state, "cd C")
    T.has(c, "cd Cellar ")
    T.has(c, "cd Conservatory ")
    T.not_has(c, "cd Library ")
end)

T.test("cd does not suggest hidden rooms", function()
    local state = make_state("study", {"study", "foyer"})
    local c = completions(state, "cd ")
    for _, v in ipairs(c) do
        T.ok(not v:find("closet"), "hidden .closet should not appear: " .. v)
    end
end)

-- -----------------------------------------------------------------------
T.suite("cd / ls — path completion with ../")

T.test("cd .. offers ../ continuation", function()
    local state = make_state("library")
    local c = completions(state, "cd ..")
    T.has(c, "cd ../")
end)

T.test("cd . offers ../ continuation", function()
    local state = make_state("library")
    local c = completions(state, "cd .")
    T.has(c, "cd ../")
end)

T.test("cd ../ from library shows foyer's exits", function()
    local state = make_state("library")
    local c = completions(state, "cd ../")
    -- foyer's exits are library, study, conservatory, cellar
    T.has(c, "cd ../Library ")
    T.has(c, "cd ../Cellar ")
    T.has(c, "cd ../Study ")
    T.has(c, "cd ../Conservatory ")
end)

T.test("cd ../C from library filters to C-prefixed rooms", function()
    local state = make_state("library")
    local c = completions(state, "cd ../C")
    T.has(c, "cd ../Cellar ")
    T.has(c, "cd ../Conservatory ")
    T.not_has(c, "cd ../Library ")
    T.not_has(c, "cd ../Study ")
end)

T.test("cd ../ from conservatory includes bedroom (child of conservatory via foyer)", function()
    -- from conservatory: .. = foyer; foyer's exits include library, study, conservatory, cellar
    local state = make_state("conservatory")
    local c = completions(state, "cd ../")
    T.has(c, "cd ../Cellar ")
    T.has(c, "cd ../Library ")
end)

T.test("ls ../ from study shows foyer's exits", function()
    local state = make_state("study")
    local c = completions(state, "ls ../")
    T.has(c, "ls ../Cellar ")
    T.has(c, "ls ../Library ")
end)

-- -----------------------------------------------------------------------
T.suite("mv / cp — destination room completion")

T.test("mv dst suggests visited rooms", function()
    local state = make_state("conservatory", {"conservatory", "foyer", "cellar"})
    local c = completions(state, "mv tea_service.txt ")
    T.has(c, "mv tea_service.txt Cellar ")
    T.has(c, "mv tea_service.txt Foyer ")
    T.not_has(c, "mv tea_service.txt Library ")  -- not visited
end)

T.test("mv dst offers ./ shorthand", function()
    local state = make_state("conservatory", {"conservatory"})
    local c = completions(state, "mv tea_service.txt ")
    T.has(c, "mv tea_service.txt ./ ")
end)

T.test("mv dst .. offers ../ continuation", function()
    local state = make_state("conservatory", {"conservatory", "foyer", "cellar"})
    local c = completions(state, "mv tea_service.txt ..")
    T.has(c, "mv tea_service.txt ../")
end)

T.test("mv dst ../ shows visited rooms under parent", function()
    local state = make_state("conservatory", {"conservatory", "foyer", "cellar", "library"})
    local c = completions(state, "mv tea_service.txt ../")
    T.has(c, "mv tea_service.txt ../Cellar ")
    T.has(c, "mv tea_service.txt ../Library ")
    T.not_has(c, "mv tea_service.txt ../Study ")  -- not visited
end)

T.test("mv dst ../C filters to visited C-prefixed rooms", function()
    local state = make_state("library", {"library", "foyer", "cellar", "conservatory"})
    local c = completions(state, "mv torn_letter.txt ../C")
    T.has(c, "mv torn_letter.txt ../Cellar ")
    T.has(c, "mv torn_letter.txt ../Conservatory ")
    T.not_has(c, "mv torn_letter.txt ../Library ")
end)

T.test("cp dst ../ works the same as mv", function()
    local state = make_state("library", {"library", "foyer", "cellar"})
    local c = completions(state, "cp torn_letter.txt ../")
    T.has(c, "cp torn_letter.txt ../Cellar ")
end)

-- -----------------------------------------------------------------------
T.suite("cat / rm — file completion")

T.test("cat suggests current room files", function()
    local state = make_state("library")
    local c = completions(state, "cat ")
    T.has(c, "cat torn_letter.txt ")
    T.has(c, "cat bookshelf_log.txt ")
end)

T.test("cat partial filters files", function()
    local state = make_state("library")
    local c = completions(state, "cat t")
    T.has(c, "cat torn_letter.txt ")
    T.not_has(c, "cat bookshelf_log.txt ")
end)

T.test("rm suggests current room files", function()
    local state = make_state("cellar")
    local c = completions(state, "rm ")
    T.has(c, "rm bloody_glove.txt ")
    T.has(c, "rm wine_inventory.txt ")
end)

-- -----------------------------------------------------------------------
T.suite("accuse completion")

T.test("accuse with no partial lists all suspects", function()
    local state = make_state("foyer")
    local c = completions(state, "accuse ")
    T.has(c, "accuse Dr. Reginald Croft")
    T.has(c, "accuse Lady Vivienne Ashworth")
end)

T.test("accuse partial filters suspects", function()
    local state = make_state("foyer")
    local c = completions(state, "accuse Dr")
    T.has(c, "accuse Dr. Reginald Croft")
    T.not_has(c, "accuse Lady Vivienne Ashworth")
end)

-- -----------------------------------------------------------------------
T.suite("grep — file completion skips pattern slot")

T.test("grep with no pattern returns nothing", function()
    local state = make_state("library")
    local c = completions(state, "grep ")
    T.eq(#c, 0)
end)

T.test("grep with pattern typed suggests files", function()
    local state = make_state("library")
    local c = completions(state, "grep digitalis ")
    T.has(c, "grep digitalis torn_letter.txt ")
end)
