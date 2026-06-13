-- meta.lua — help, echo, exit, accuse

local World = require("world")
local Screen = require("screen")

local function help(state, _)
    local lines = {
        "Available commands:",
        "  ls [-a]                  list the contents of this room (-a shows hidden)",
        "  pwd                      print current room path",
        "  cwd                      print previous room path",
        "  cd <room>                move to an adjacent room",
        "  cd .. / cd ~             go up to the Foyer (root / home)",
        "  cd ../<room>             go up then into a room (e.g. cd ../study)",
        "  cd -                     return to the previous room",
        "  cd                       return to the Foyer",
        "  echo <text>              repeat text back",
        "  exit                     quit the game",
        "  help                     show this list",
        "  accuse <name>            name the murderer",
    }
    table.insert(lines, "  cat <file>               read a piece of evidence")
    if state.unlocked.grep then
        table.insert(lines, "  grep [flags] <pattern> <file>   search a file")
        table.insert(lines, "  grep -r <pattern>               search all visited rooms")
        table.insert(lines, "  grep -r -a <pattern>            include hidden files")
        table.insert(lines, "  grep <pattern> *                all files in this room")
        table.insert(lines, "  grep <pattern> .[^.]*           hidden files only")
        table.insert(lines, "  flags: -v invert  -n line nos  -l filenames only")
    else
        table.insert(lines,
            "  grep ...                 (not yet — read two pieces of evidence first)")
    end
    table.insert(lines, "  find <name>              search for a file across visited rooms")
    table.insert(lines, "  diff <file1> <file2>     compare two files (both must be cat'd first)")
    table.insert(lines, "  rm <file>                destroy evidence (irreversible; rm -f skips prompt)")
    table.insert(lines, "  cp <file> <room>         copy a file to a visited room")
    table.insert(lines, "  mv <file> <room>         move a file to a visited room")
    table.insert(lines, "  chmod <mode> <target>    set permissions on a room or file")
    table.insert(lines, "")
    table.insert(lines, "Tip: filenames you find with `ls` are case-sensitive.")
    table.insert(lines, "Tip: `accuse` takes a surname or a full name.")
    return table.concat(lines, "\n")
end

local function echo(_, args)
    return table.concat(args, " ")
end

local function exit(_, _)
  Screen.set("play")
    return ""
end

local function accuse(state, args)
    if #args == 0 then
        return "Usage: accuse <name>\n"
            .. "You must name one of the four guests."
    end
    local input = table.concat(args, " ")
        :lower():gsub("^%s+", ""):gsub("%s+$", "")
    local resolved = World.accuse_aliases[input]
    if not resolved then
        return "You glance around the drawing room. No one there\n"
            .. "answers to that name. Try a surname, or a full name."
    end

    if resolved == World.murderer then
        state.won = true
        state.win_time = state.elapsed
        state.win_commands = state.command_count
        return "You point your finger across the drawing room at\n"
            .. "Dr. Reginald Croft.\n\n"
            .. "His face goes white. His hand drifts toward his coat\n"
            .. "pocket, then stops. He sits — very slowly — upon the\n"
            .. "chaise, and the fight goes out of him.\n\n"
            .. "  \"I never meant... I never meant for it to come to\n"
            .. "   this. He was going to ruin me.\"\n\n"
            .. "He confesses to all of it: the embezzlement from the\n"
            .. "village medical fund, the lethal dose, the gloves he\n"
            .. "wore to handle the bottle, the one he panicked and\n"
            .. "hid in the cellar before the body had even gone cold.\n\n"
            .. "The case is yours."
    end

    return "You point your finger at " .. resolved .. ".\n\n"
        .. "They blanch, sputter, and then their eyes go cold:\n"
        .. "  \"You have no proof — and you are wrong.\"\n\n"
        .. "The room is silent. The real killer relaxes, just a little.\n"
        .. "(Keep looking. The truth is in the evidence.)"
end

return { help = help, echo = echo, exit = exit, accuse = accuse }
