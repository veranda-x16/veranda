# MIDI Player

MIDI files (type 0 and 1) on the YM2151 and ZSM files on the YM2151 and
VERA's PSG, in a native Veranda window (DECISIONS V205). The engines are
MooingLemur's: Melodius's MIDI engine and ZSMKit v3 (`vendor/`, MIT, with
their notices and the commits they came from); the window, the playlist
and the glue are Veranda's. The manual: `docs/manual/MIDI-Player.md`.

## How it fits

- **Main RAM**: `main.c` (the start, the folder's entries, a song read
  into RAM banks, playing), `engine.s` (the tick and the engines' calls),
  Melodius's `midi.s` and `math.s`, `../sysui/sysui.c`; about 22 KB of
  the 30 KB below the C stack.
- **Overlay 1** (appBank): `ui.c`, the window.
- **Overlays 2 and 3**: ZSMKit's two banks, run in place. A banked
  program's overlays are one run of banks (record n in bank first + n),
  so the two are adjacent, as ZSMKit v3 needs.
- **RAM banks**: the overlays, two for the playlist, and a song whole in
  as many as it takes (one run: both engines read on from bank to bank).
- **The tick**: `intTopVector`, 60 a second, in the interrupt (menus,
  boxes and redrawing do not stop it). ROM bank $0A (the audio calls)
  has no interrupt vectors in R49, so it is mapped only with the
  interrupt off; every call from the main loop runs with it off.
- **Alt+Tab**: the switcher calls nothing of a program aside, so
  `asideVector` pauses the song (its voices released) and the main loop
  starts it again when the program comes back.

## Building

    make SDK=../../build/sdk          # MIDIPlay.cvt
    make test SDK=../../build/sdk     # the gate's test build

The gate: `tools/gate_midiplay.sh` (R49, 512 KB: test songs made by
`tests/midiplay_files.py`; every note at its frame, pause, Play next,
Alt+Tab, quit; the emulator's recording for sound and silence).

MIT licence (see LICENSE).
