# Sound System

## Architecture

Single `sound_manager.go` with embedded Sound components for each effect.
Added to both `soliter.collection` and `soliter1.collection`.

**Module:** `main/Scripts/sfx.lua` — unified API for playing sounds.

### Cross-collection workaround
GUI scripts cannot call `sound.play()` on GO from another collection.
`sfx.lua` uses `queue()` for GUI sounds — sets `M.pending`, polled by `main.script` `update()`.

## Sound files

All files in `assets/sounds/` (WAV, mono, 44100Hz).
Generated via Python synthesis. Can be replaced with Kenney/Freesound assets.

| File | Event | Where triggered |
|------|-------|----------------|
| `card_pick.wav` | Card grabbed | `card.script` → `start_drag` |
| `card_drop.wav` | Card placed | `card.script` → `drop_success` |
| `card_error.wav` | Invalid move | `card.script` → `drop_failed` |
| `card_deal.wav` | Deal start | `main.script` → `deal_cards()` |
| `dragon_collect.wav` | Dragons collected | `dragon_button.script` → `get_dragon_cards` |
| `flower_auto.wav` | Auto-move (flower/base) | `card.script` → `drop_success` with `animation` |
| `victory.wav` | Win | `main.script` → 3 paths (normal/auto-finish/tutorial) |
| `button_click.wav` | UI button press | `ui.gui_script` → via `sfx.queue()` |
| `auto_finish.wav` | Auto-finish per card | `main.script` → `auto_finish_step()` |

## Usage

From game scripts (same collection):
```lua
local sfx = require("main.Scripts.sfx")
sfx.card_pick()
sfx.victory()
```

From GUI scripts (cross-collection):
```lua
local sfx = require("main.Scripts.sfx")
sfx.button_click()  -- uses queue(), polled by main.script
```

## Replacing sounds

Drop new WAV/OGG files into `assets/sounds/` with the same names.
If switching to OGG, update paths in `main/Game Objects/sound_manager.go`.

## Free sound sources

- **Kenney.nl** — CC0: `casino-audio`, `ui-audio` packs
- **Freesound.org** — filter by CC0 license
- **Mixkit.co** — free, no attribution
- **jsfxr** (`sfxr.me`) — generate and export WAV

## Ambient music (2026-11-04)

`assets/music/quiet-garden.ogg`: original 96-second stereo composition, 60 BPM,
D major / B minor, soft plucks and pads, no percussion or sampled recordings.
The reproducible score and synthesis are in `tools/compose-garden.py` and
`assets/music/score.json`. Run `python3 tools/compose-garden.py` with ffmpeg;
this also writes a 44.1kHz / 16-bit WAV master into ignored `build/music/`.
The installed ffmpeg uses its native experimental Vorbis encoder, explicitly
selected by the script. Ogg is approximately 497 KiB. Note/reverb tails wrap
around the 96-second boundary; startup fades in over 0.8 s, mute over 0.18 s.

`main/main.collection` owns a persistent `music.go` with controller + looping
sound. It survives proxy unload/restart and keeps one voice. The GUI's first
real touch/click enables the track; the music button toggles it on every screen.
The preference is saved separately from game progress (`audio`, key `music`).
Disabling pauses after the fade; enabling resumes the same voice. Final stops it.
The existing HTML5 audio-focus guard suspends all Web Audio contexts on blur or
hidden state, covering music too. Production Yandex ads are not exercised here.

Defold API contract: [sound playback and gain](https://defold.com/manuals/sound/).
Browser scenario `music` probes actual PCM at the mixer output, including release;
Lua start-count assertions apply only to debug, since release strips print calls.
`focus` independently checks actual AudioContext suspended/running states.
Mobile runs are Chrome touch emulation, not a physical device listening test.
