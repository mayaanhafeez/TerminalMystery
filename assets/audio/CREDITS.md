# Audio credits

Every file below is CC0 / public domain. No attribution is legally required, but
sources are credited here anyway and per the pack authors' own requests. All
files were converted to mono 44.1kHz Ogg Vorbis with `ffmpeg` (resample/trim)
+ `oggenc` (Vorbis encode — the `ffmpeg` build on hand only ships an
experimental stereo-only native Vorbis encoder, so `vorbis-tools` was
installed via `brew install vorbis-tools` to get a real mono encoder).

Two files (`amb/party_muffled.ogg`, `amb/arcade_hum.ogg`) are marked
**APPROXIMATION** below: no CC0 recording of an actual muffled party/crowd or
an actual arcade-cabinet hum turned up after a real search effort, so a
generic CC0 noise/machine loop was used as a stand-in. See
`.claude/for_ayaan.txt` for the punch list.

## Sources

| Pack / page | Author | License | URL |
| --- | --- | --- | --- |
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
| enter.ogg | Kenney Interface Sounds | confirmation_002.ogg | CC0 |
| back.ogg | Kenney Interface Sounds | back_002.ogg | CC0 |
| tick.ogg | Kenney Interface Sounds | tick_001.ogg | CC0 |
| tick2.ogg | Kenney Interface Sounds | tick_004.ogg | CC0 |
| error.ogg | Kenney Interface Sounds | error_008.ogg | CC0 |
| crt_on.ogg | Kenney Sci-fi Sounds | lowFrequency_explosion_000.ogg | CC0 |
| crt_off.ogg | Kenney Sci-fi Sounds | lowFrequency_explosion_001.ogg | CC0 |
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
| screen_on.ogg | Kenney Sci-fi Sounds | computerNoise_000.ogg | CC0 |
| screen_off.ogg | Kenney Sci-fi Sounds | computerNoise_002.ogg | CC0 |
| slack_blip.ogg | Kenney Digital Audio | twoTone1.ogg | CC0 |
| popup_open.ogg | Kenney Interface Sounds | open_003.ogg | CC0 |
| popup_close.ogg | Kenney Interface Sounds | close_003.ogg | CC0 |
| step.ogg | Kenney Impact Sounds | footstep_wood_000.ogg | CC0 |
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
| room_tone.ogg | 100 CC0 SFX #2 (OpenGameArt) | sfx100v2_loop_ambient_01.ogg | CC0 | used as-is, ~10s |
| server_fans.ogg | 100 CC0 SFX #2 (OpenGameArt) | sfx100v2_loop_machine_02.ogg | CC0 | used as-is, ~10.6s |
| cellar_drip.ogg | Loopable Dungeon Ambience (OpenGameArt) | dungeon_ambient_1.ogg | CC0 | 12s excerpt (20s-32s) of the 94s source |
| birds_glass.ogg | Ambient Bird Sounds (OpenGameArt) | birds-isaiah658.ogg | CC0 | 12s excerpt (5s-17s) of the 30.7s source |
| compressor.ogg | 30 CC0 SFX loops (OpenGameArt) | pump_01.ogg | CC0 | source looped x2 (~6.2s) for a fuller bed |
| party_muffled.ogg | 30 CC0 SFX loops (OpenGameArt) | noise_01.ogg | CC0 | **APPROXIMATION** — generic ambient noise texture, not an actual party/crowd recording; no CC0 muffled-party loop was found |
| arcade_hum.ogg | 30 CC0 SFX loops (OpenGameArt) | machine_09.ogg | CC0 | **APPROXIMATION** — generic electronic machine loop, not an actual arcade-cabinet recording; source looped x3 (~8.1s); no CC0 arcade-hum loop was found |

## Exceptions requiring sign-off

None. Every file above is CC0. No CC-BY or other attribution-required
material was used.
