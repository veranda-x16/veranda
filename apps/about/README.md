# About this X16

What this machine is and how it is doing, in one window (DECISIONS V119),
for a look or for a bug report.

## Using it

- **This machine**: Veranda's version, API level and the build it came
  from; the KERNAL ROM's release (R49 ...: its version byte at `$FF80`);
  the machine (the Commander X16, or x16emu: the emulator reports its own
  release as VERA's version); the CPU's speed, measured against VERA's
  frame; VERA's version (VERA 0.3.1 and later say it) and the SMC's
  firmware.
- **Memory**: the RAM there is (512 KB is 64 banks of 8 KB); the
  system's share (Veranda's kernel banks and their copy, bank 0); the
  programs put aside with Alt+Tab, each with its banks; this program's;
  the rest in use (fonts loaded into RAM, the desktop's picture lent);
  free.
- **The SD card**: its name, the size of its FAT32 partition and of the
  whole card, the free space.
- **The network card**: a UART where TexElec's Serial & ESP32 Network
  Card puts one (`$9FE0` from the factory), or none. Nothing is sent to
  the modem unless you press **Ask the modem**: then it says `AT` at each
  rate Zimodem may be at (115200 down to 9600) and `ATI` at the one that
  answered, and shows the firmware's line (Zimodem's version: Veranda
  Claude and Veranda Ask need one with `ATCS`). Nothing that changes the
  modem is sent (no `ATB`, `ATZ` or profile). Esc stops it.
- **The clock**: the date and time, and the time since the last reset.

The clock, the memory and the time since reset are drawn again every
second; **Refresh** (or R) reads everything again. **Copy** (or C; Edit >
Copy all) puts it all on the clipboard as text, a line each, to paste
into a bug report (Veranda Edit, Note Pad ...).

**Alt+Tab** puts it aside at any time; a question to the modem running
then is dropped ("interrupted"), the UART turned off.

## Building

    make SDK=../../build/sdk          # About.cvt
    make test SDK=../../build/sdk     # the gate's test build

The gate: `tools/gate_about.sh` (R49: 512 KB and 2 MB, the host folder
and an SD card image, the modem emulator).

MIT licence (see LICENSE).
