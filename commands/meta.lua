-- meta.lua — help, echo, exit, accuse

local World = require("world")

local function help(state, _)
    local lines = {
        "Available commands:",
        "  ls [-a]                  list the contents of this room (-a shows hidden)",
        "  pwd                      print current room path",
        "  cwd                      print previous room path",
        "  cd <room>                move to an adjacent room",
        "  cd .. / cd ~             go up to the Entrance Hall (root / home)",
        "  cd ../<room>             go up then into a room (e.g. cd ../den)",
        "  cd -                     return to the previous room",
        "  cd                       return to the Entrance Hall",
        "  echo <text>              repeat text back",
        "  exit                     quit the game",
        "  help                     show this list",
        "  accuse <name>            name the murderer",
        "  vim/nvim/vi              open a good editor to take notes"
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
    table.insert(lines, "  chmod <mode> <target>    set permissions (chmod +w <file> makes it writable)")
    table.insert(lines, "  sed 's/old/new/' <file>  print the file with a substitution applied")
    table.insert(lines, "  sed -i 's/old/new/g' <f> edit the file in place (needs chmod +w first)")
    table.insert(lines, "")
    table.insert(lines, "Tip: filenames you find with `ls` are case-sensitive.")
    table.insert(lines, "Tip: `accuse` takes a surname or a full name.")
    return table.concat(lines, "\n")
end

local function echo(_, args)
    return table.concat(args, " ")
end

-- Open the notes scratch pad. There is only ever the one file, so any arguments
-- are ignored. Like `exit`, this can't draw anything itself — it just tells the
-- game screen to open the editor (which freezes the terminal until :q).
local function vim(_, _)
  GameScreen.open_vim()
  return ""
end

local function nvim(state, args)
  return vim(state, args)
end

local function vi(state, args)
  return vim(state, args)
end

local function emacs(_,_)
  return "use vim to edit files"
end

local function nano(_,_)
    local lines = {}
    table.insert(lines, "seriously...")
    table.insert(lines, "USE VIM!")
  return table.concat(lines, "\n")
end

local function exit(_, args)
  if args[1] == "save" then
    Save.save_state(GameScreen.state, "save_data.txt")
    GameScreen.request_exit_to_play()
    return ""
  elseif args[1] == "nosave" then
    GameScreen.request_exit_to_play()
    return ""
  end
  -- Bare `exit`: open the interactive Y/n save prompt (handled in game.lua).
  GameScreen.begin_exit_prompt()
  return ""
end

-- The four guests, one per line, for the usage and unknown-name replies. Comes
-- from World.suspects rather than the alias table: aliases are many-to-one, so
-- dumping their keys would list each suspect four times.
local function suspect_list()
    local lines = {}
    for _, name in ipairs(World.suspects) do
        table.insert(lines, "  " .. name)
    end
    return table.concat(lines, "\n")
end

local function accuse(state, args)
    if #args == 0 then
        return "Usage: accuse <name>\n"
            .. "You must name one of the four guests:\n"
            .. suspect_list()
    end
    local input = table.concat(args, " ")
        :lower():gsub("^%s+", ""):gsub("%s+$", "")
    local resolved = World.accuse_aliases[input]
    if not resolved then
        return "You scan the room. No one here answers to that name.\n"
            .. "The four guests are:\n"
            .. suspect_list() .. "\n"
            .. "A first name, a surname, or a full name all work."
    end

    if resolved == World.murderer then
        state.won = true
        state.win_time = state.elapsed
        state.win_commands = state.command_count
        return "You turn to Daniel Lin.\n\n"
            .. "He doesn't argue. He sets down his laptop, the solo\n"
            .. "Balatro run still paused on the screen, and lets out a\n"
            .. "long breath.\n\n"
            .. "  \"He was going to take it to Trent. The billing, the\n"
            .. "   vendor account — all of it. I'd have lost everything.\"\n\n"
            .. "He admits the rest: the $310K he skimmed through Meridian\n"
            .. "Compute, the foxglove extract from his own HRV stack, the\n"
            .. "kombucha in the Den at 10:00, the badge scan in the cellar,\n"
            .. "and the log he tried to scrub — swapping his handle for a\n"
            .. "service account so no one would look twice.\n\n"
            .. "The case is yours."
    end

    return "You point your finger at " .. resolved .. ".\n\n"
        .. "They blink, then their expression hardens:\n"
        .. "  \"You've got the wrong person, and no proof.\"\n\n"
        .. "The room goes quiet. The real killer relaxes, just a little.\n"
        .. "(Keep looking. The truth is in the evidence.)"
end

return { help = help, echo = echo, exit = exit, accuse = accuse, vim = vim, vi=vi, nvim = nvim, emacs=emacs, nano=nano}
