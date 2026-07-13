-- banner.lua
-- ASCII-art title banner "TERMINAL MYSTERY" (figlet "ansi_regular", block
-- style). Shared by the boot screen (revealed line-by-line at the end of the
-- fake boot log) and the play/title screen (drawn centered in place of the old
-- text title). Pure data — no LÖVE dependency.

local TERMINAL = {
	"████████ ███████ ██████  ███    ███ ██ ███    ██  █████  ██",
	"   ██    ██      ██   ██ ████  ████ ██ ████   ██ ██   ██ ██",
	"   ██    █████   ██████  ██ ████ ██ ██ ██ ██  ██ ███████ ██",
	"   ██    ██      ██   ██ ██  ██  ██ ██ ██  ██ ██ ██   ██ ██",
	"   ██    ███████ ██   ██ ██      ██ ██ ██   ████ ██   ██ ███████",
}

local MYSTERY = {
	"███    ███ ██    ██ ███████ ████████ ███████ ██████  ██    ██",
	"████  ████  ██  ██  ██         ██    ██      ██   ██  ██  ██",
	"██ ████ ██   ████   ███████    ██    █████   ██████    ████",
	"██  ██  ██    ██         ██    ██    ██      ██   ██    ██",
	"██      ██    ██    ███████    ██    ███████ ██   ██    ██",
}

-- Combined banner: TERMINAL, a spacer line, then MYSTERY.
local lines = {}
for _, l in ipairs(TERMINAL) do
	lines[#lines + 1] = l
end
lines[#lines + 1] = ""
for _, l in ipairs(MYSTERY) do
	lines[#lines + 1] = l
end

return {
	terminal = TERMINAL,
	mystery = MYSTERY,
	lines = lines,
}
