# Audio credits

Every file below is CC0 / public domain. No attribution is legally required, but
sources are credited here anyway and per the pack authors' own requests. All
files were converted to mono 44.1kHz Ogg Vorbis with `ffmpeg` (resample/trim)
+ `oggenc` (Vorbis encode — the `ffmpeg` build on hand only ships an
experimental stereo-only native Vorbis encoder, so `vorbis-tools` was
installed via `brew install vorbis-tools` to get a real mono encoder).

Two files (`amb/party_muffled.ogg`, `amb/arcade_hum.ogg`) are marked
**DERIVED** below: no CC0 recording of an actual muffled party/crowd or an
actual arcade-cabinet hum turned up after a real search effort, so both are cut
from TinyWorlds' CC0 "Scifi City" crowd/urban loop — `party_muffled` is
low-passed to read as a party heard through walls, `arcade_hum` keeps the full
band for a livelier game-room texture. Real crowd/electronic ambience rather
than the generic noise/machine stand-ins used before. See
`.claude/for_ayaan.txt` for the punch list.

Three files are marked **synthesized (this repo)** below — `ui/crt_on.ogg`,
`ui/crt_off.ogg` and `amb/room_tone.ogg`. These are original works generated
with `ffmpeg` (the "Original file" column gives the recipe) and are released CC0
along with everything else; no third-party sample is involved.

## Sources

| Pack / page | Author | License | URL |
| --- | --- | --- | --- |
| Keyboard Soundpack #1 | unicaegames | CC0 | https://opengameart.org/content/keyboard-soundpack-1-typing-and-single-keystrokes |
| 50 CC0 Sci-Fi SFX | rubberduck | CC0 | https://opengameart.org/content/50-cc0-sci-fi-sfx |
| Scifi City - Ambient Loop | TinyWorlds | CC0 | https://opengameart.org/content/scifi-city-ambient-loop |
| Interface Sounds | Kenney | CC0 | https://kenney.nl/assets/interface-sounds |
| UI Audio | Kenney | CC0 | https://kenney.nl/assets/ui-audio |
| Digital Audio | Kenney | CC0 | https://kenney.nl/assets/digital-audio |
| Sci-fi Sounds | Kenney | CC0 | https://kenney.nl/assets/sci-fi-sounds |
| Impact Sounds | Kenney | CC0 | https://kenney.nl/assets/impact-sounds |
| Opening and Closing a Map Sounds | Spring Spring | CC0 | https://opengameart.org/content/opening-and-closing-a-map-sounds |
| Book Flip Sounds | Voltiment555 | CC0 | https://opengameart.org/content/book-flip-sounds |
| Loopable Dungeon Ambience | JaggedStone | CC0 | https://opengameart.org/content/loopable-dungeon-ambience |
| Ambient Bird Sounds | isaiah658 | CC0 | https://opengameart.org/content/ambient-bird-sounds |
| 100 CC0 SFX #2 | rubberduck | CC0 | https://opengameart.org/content/100-cc0-sfx-2 |
| 30 CC0 SFX loops | rubberduck | CC0 | https://opengameart.org/content/30-cc0-sfx-loops |

## File-by-file

### ui/

| File | Source pack | Original file | License |
| --- | --- | --- | --- |
| key_1.ogg | Kenney UI Audio | click1.ogg | CC0 |
| key_2.ogg | Kenney UI Audio | click2.ogg | CC0 |
| key_3.ogg | Kenney UI Audio | click3.ogg | CC0 |
| type_1.ogg | Keyboard Soundpack #1 | Single Keys/keypress-001.wav (attack-trimmed) | CC0 |
| type_2.ogg | Keyboard Soundpack #1 | Single Keys/keypress-008.wav (attack-trimmed) | CC0 |
| type_3.ogg | Keyboard Soundpack #1 | Single Keys/keypress-013.wav (attack-trimmed) | CC0 |
| enter.ogg | Keyboard Soundpack #1 | Single Keys/keypress-016.wav | CC0 |
| back.ogg | Kenney Interface Sounds | back_002.ogg | CC0 |
| tick.ogg | Kenney Interface Sounds | tick_001.ogg | CC0 |
| tick2.ogg | Kenney Interface Sounds | tick_004.ogg | CC0 |
| error.ogg | Kenney Interface Sounds | error_008.ogg | CC0 |
| crt_on.ogg | synthesized (this repo) | ffmpeg: static crackle + 62Hz degauss thunk + 11kHz flyback whine fade-in | CC0 |
| crt_off.ogg | synthesized (this repo) | ffmpeg: switch clunk + 900→110Hz flyback collapse + whine die-off | CC0 |
| bell.ogg | Kenney Interface Sounds | bong_001.ogg | CC0 |
| write_ok.ogg | Kenney Interface Sounds | confirmation_001.ogg | CC0 |
| mode_tick.ogg | Kenney UI Audio | switch5.ogg | CC0 |
| page_turn.ogg | Book Flip Sounds (OpenGameArt) | BookFlip5.wav | CC0 |
| unlock_ping.ogg | Kenney Digital Audio | highUp.ogg | CC0 |
| win.ogg | Kenney Digital Audio | pepSound1.ogg | CC0 |
| record.ogg | Kenney Digital Audio | pepSound3.ogg | CC0 |

### world/

| File | Source pack | Original file | License |
| --- | --- | --- | --- |
| paper_open.ogg | Opening and Closing a Map Sounds (OpenGameArt) | snd_use_map.wav | CC0 |
| paper_close.ogg | Opening and Closing a Map Sounds (OpenGameArt) | snd_close_map.wav | CC0 |
| book_open.ogg | Book Flip Sounds (OpenGameArt) | BookFlip1.wav | CC0 |
| book_close.ogg | Book Flip Sounds (OpenGameArt) | BookFlip9.wav | CC0 |
| screen_on.ogg | 50 CC0 Sci-Fi SFX | loop_machine_01.ogg (1.1s excerpt, faded) | CC0 |
| screen_off.ogg | 50 CC0 Sci-Fi SFX | loop_machine_01.ogg (reversed, 0.95s, faded) | CC0 |
| slack_blip.ogg | Kenney Digital Audio | twoTone1.ogg | CC0 |
| popup_open.ogg | Kenney Interface Sounds | open_003.ogg | CC0 |
| popup_close.ogg | Kenney Interface Sounds | close_003.ogg | CC0 |
| step.ogg | Kenney Impact Sounds | footstep_wood_000.ogg | CC0 |
| step_1.ogg | Kenney Impact Sounds | footstep_wood_001.ogg | CC0 |
| step_2.ogg | Kenney Impact Sounds | footstep_wood_002.ogg | CC0 |
| step_3.ogg | Kenney Impact Sounds | footstep_wood_003.ogg | CC0 |
| step_4.ogg | Kenney Impact Sounds | footstep_wood_004.ogg | CC0 |
| door_new.ogg | Kenney Sci-fi Sounds | doorOpen_000.ogg | CC0 |
| locked.ogg | Kenney Sci-fi Sounds | forceField_002.ogg | CC0 |
| badge_ok.ogg | Kenney Interface Sounds | confirmation_004.ogg | CC0 |
| search.ogg | Kenney Digital Audio | phaserUp2.ogg | CC0 |
| edit_commit.ogg | Kenney Interface Sounds | click_003.ogg | CC0 |
| move.ogg | Kenney Interface Sounds | drop_002.ogg | CC0 |
| warn.ogg | Kenney Interface Sounds | error_003.ogg | CC0 |
| destroy.ogg | Kenney Sci-fi Sounds | explosionCrunch_002.ogg | CC0 |
| unlock_heavy.ogg | Kenney Impact Sounds | impactMetal_heavy_002.ogg | CC0 |
| unlock_fail.ogg | Kenney Digital Audio | zapTwoTone2.ogg | CC0 |

### amb/

| File | Source pack | Original file | License | Notes |
| --- | --- | --- | --- | --- |
| room_tone.ogg | synthesized (this repo) | ffmpeg: low-passed brown noise + faint 100Hz hum, 12s | CC0 | smooth HVAC bed (foyer / home office / closet); the old rubberduck loop was bright and wavering |
| server_fans.ogg | 100 CC0 SFX #2 (OpenGameArt) | sfx100v2_loop_machine_02.ogg | CC0 | used as-is, ~10.6s |
| cellar_drip.ogg | Loopable Dungeon Ambience (OpenGameArt) | dungeon_ambient_1.ogg | CC0 | 12s excerpt (20s-32s) of the 94s source |
| birds_glass.ogg | Ambient Bird Sounds (OpenGameArt) | birds-isaiah658.ogg | CC0 | 12s excerpt (5s-17s) of the 30.7s source |
| compressor.ogg | 30 CC0 SFX loops (OpenGameArt) | pump_01.ogg | CC0 | source looped x2 (~6.2s) for a fuller bed |
| party_muffled.ogg | Scifi City - Ambient Loop (OpenGameArt) | busy_cyberworld.ogg (1.5s–16.5s, low-passed ~750Hz) | CC0 | **DERIVED** — a crowd/urban CC0 loop low-passed to read as a party through walls; no CC0 muffled-party recording was found |
| arcade_hum.ogg | Scifi City - Ambient Loop (OpenGameArt) | busy_cyberworld.ogg (15s–27s, full band) | CC0 | **DERIVED** — the same crowd/electronic CC0 loop kept full-band for a livelier game-room texture; no CC0 arcade-cabinet recording was found |

## Exceptions requiring sign-off

None. Every file above is CC0. No CC-BY or other attribution-required
material was used.
