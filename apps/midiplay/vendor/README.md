# MooingLemur's code in MIDI Player

Both are MIT, Copyright (c) 2023 MooingLemur; each folder keeps its
LICENSE file.

## melodius/ — Melodius's MIDI engine

From [github.com/mooinglemur/melodius](https://github.com/mooinglemur/melodius)
at commit `3720fa5028c5df6d7ff3bfed1fb7a1413131fb82` (2025-12-14, "move to
ZSMKit v3 dev build"): `src/midi.s`, `src/math.s`, `src/x16.inc`,
`src/audio.inc`, `src/macros.inc`, and `LICENSE`.

Only the engine is taken (no file browser, tiles, sprites or
visualisations: MIDI Player's window is Veranda's own). Changes, each
marked "Veranda" in the files:

- `midi.s`: the player's volume (`midi_master`, `add_master`,
  `midi_set_master`: an attenuation added to every YM channel's); the
  exports the window reads (the file's type and tracks, the tracks'
  places for the progress bar); `debug_byte` kept in the file (it was
  `visualizations.s`'s); the test build's audio calls (`../audio_t.inc`).
- `macros.inc`: the border-colour macros do nothing (VERA's `$9F2C` is
  another register when DCSEL is not 0, as Veranda may have it).

`math.s`, `x16.inc` and `audio.inc` are as they were.

## zsmkit/ — ZSMKit v3

From [github.com/mooinglemur/ZSMKit](https://github.com/mooinglemur/ZSMKit)
at commit `4c3593d3b09cc228b51516320832f12bd68da50f` (2025-12-14, "misc
documentation improvements"): `src/` (`zsmkit.s` and its include files),
`zsmkit.cfg` and `LICENSE`, unchanged. MIDI Player's Makefile builds it
as ZSMKit's own Makefile does (ca65, ld65 with `zsmkit.cfg`); the binary
is the same, byte for byte, as Melodius's `extern/zsmkit-a000.bin` at the
commit above. `../zsmsplit.py` makes its two banks two overlay records.
