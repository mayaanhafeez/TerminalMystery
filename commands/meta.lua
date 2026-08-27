-- meta.lua — help, echo, exit, accuse

local World = require("world")
local Audio = require("audio")

-- `help vim` (also `help nvim` / `help vi`). Keyed off the same three names the
-- editor answers to, since a player who only knows one of them will type that.
local VIM_HELP = {
    "vim — the notes editor.",
    "",
    "It opens beside the terminal and takes the keyboard with it: the",
    "terminal is frozen until you quit back out. There is only one scratch",
    "pad, so vim, nvim and vi all open the same notes no matter what you",
    "type after them.",
    "",
    "Getting text in:",
    "  i                        insert before the cursor",
    "  a                        insert after the cursor",
    "  o                        open a line below and insert",
    "  s                        replace the character under the cursor",
    "  Esc                      leave insert mode",
    "",
    "Moving around (in normal mode — press Esc first):",
    "  h j k l                  left, down, up, right (the arrows work too)",
    "  0                        jump to the start of the line",
    "  $                        jump to the end of the line",
    "  x                        delete the character under the cursor",
    "",
    "Commands (type : in normal mode, then Enter):",
    "  :w                       write the notes",
    "  :q                       quit — refused if you have unwritten changes",
    "  :q!                      quit and throw those changes away",
    "  :wq                      write, then quit",
    "",
    "  ctrl +  /  ctrl -        make the text bigger / smaller",
    "  ctrl 0                   back to the default size",
    "",
    "The size you pick lasts until you quit the game. Your notes are kept",
    "with the game itself: `exit save` keeps them, `exit nosave` throws away",
    "everything written this session.",
}

local function help(state, args)
    local topic = args and args[1] and args[1]:lower()
    if topic == "vim" or topic == "nvim" or topic == "vi" then
        return table.concat(VIM_HELP, "\n")
    end

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
        "  vim/nvim/vi              open a good editor to take notes",
        "                           (`help vim` for how to drive it)"
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
    -- Skipped in a terminal-only run: there is no room panel to map and no
    -- audio to level, so these are not commands there (see commands/init.lua).
    if not state.terminal_only then
        table.insert(lines, "  map [on|off]             show or hide the room map")
        table.insert(lines, "  mute                     toggle all sound on/off")
        table.insert(lines, "  volume <0-100>           set the volume (no argument reports it)")
    end
    table.insert(lines, "")
    table.insert(lines, "Tip: filenames you find with `ls` are case-sensitive.")
    table.insert(lines, "Tip: `accuse` takes a surname or a full name.")
    return table.concat(lines, "\n")
end

local function echo(_, args)
    return table.concat(args, " ")
end

local function mute(_, _)
    Audio.set_enabled(not Audio.enabled)
    return Audio.enabled and "Sound on." or "Sound off."
end

-- `map`, `map on`, `map off` — the room-panel map overlay. Drives the same
-- state flag as the Ctrl/Cmd+M shortcut, so the two never disagree.
local function map(state, args)
    local arg = args[1] and args[1]:lower()
    local shown = not state.minimap_hidden
    if arg == nil then
        state.minimap_hidden = shown
        return shown and "Map disabled" or "Map enabled"
    elseif arg == "on" then
        if shown then
            return "Map already enabled"
        end
        state.minimap_hidden = false
        return "Map enabled"
    elseif arg == "off" then
        if not shown then
            return "Map already disabled"
        end
        state.minimap_hidden = true
        return "Map disabled"
    end
    return "Usage: map [on|off]"
end

local function volume(_, args)
    if #args == 0 then
        return "Volume: " .. math.floor(Audio.volume_scale * 100 + 0.5) .. "%"
            .. (Audio.enabled and "" or " (muted — run `mute` to unmute)")
    end
    local pct = tonumber(args[1])
    if not pct then
        return "Usage: volume <0-100>"
    end
    Audio.set_volume(pct)
    return "Volume set to " .. math.floor(Audio.volume_scale * 100 + 0.5) .. "%."
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

return { help = help, echo = echo, exit = exit, accuse = accuse, vim = vim, vi=vi, nvim = nvim, emacs=emacs, nano=nano, mute = mute, volume = volume, map = map}
