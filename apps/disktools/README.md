# Disk Tools

The SD card looked after, in one window (DECISIONS V119): what the card
is, where its space went, a check of its file system that only reads,
and a clean-up of the trash and of what Veranda's own programs leave
behind. There is no formatting: the X16 starts Veranda from this card,
the only one.

## Using it

The toolbar's four tabs (or the keys 1 to 4, Tab for the next; the Tools
menu):

- **Card**: its name, the file system (FAT32, its partition in the MBR),
  its size (the partition, and the whole card from its CSD register), the
  free space (FSInfo's count, which CMDR-DOS keeps, and the DOS's own
  rounded figure), the cluster size and count, the FATs, the boot
  sector's copy of the name. **Rename...** gives the card a new name of up
  to 11 characters (CMDR-DOS's `R-H` command). On the emulator's host
  folder only its name is shown: there is no FAT under it.
- **Space use**: the folders in a folder (the card's top first), each with
  the total size of everything under it, largest first, with a bar; the
  folder's own files on a line of their own. Click a folder (or select it
  with Up and Down and press Return) to look inside it; **Up** (or
  Backspace) goes back. Counting reads one folder a pass and shows its
  progress in the status bar; **Esc** stops it (what was counted stays,
  marked as stopped). **Count again** counts afresh.
- **Check (read only)**: **Start the check** reads the FAT and every
  folder and reports what it finds. It **never writes to the card and
  repairs nothing.** It finds: a chain that starts or points past the
  card's last cluster; a cluster marked bad in a chain; a chain that runs
  into a free cluster; chains that cross (or a chain that loops); a file
  whose chain is shorter or longer than its size needs; a folder whose
  chain goes past 2 MB; the sectors where the two FATs differ; lost
  clusters (in use, but in no file or folder). FSInfo's free count is
  shown beside the FAT's own; a difference there is not an error. Esc
  stops it. It needs an SD card (or its image in the emulator), not the
  host folder.
- **Clean up**: **the trash** (`/VERANDA/.SYSTEM/TRASH`, the shell's) with
  its items listed; **Empty the trash...** asks, then deletes everything
  in it for good, as the shell's empty trash does (the TRASH folder
  stays). **Look for leftovers** walks the card for the files Veranda's
  own programs leave when a save is cut short, listed kind by kind; each
  kind is deleted only after its own OK:
  - `~VEDIT.TMP`: Veranda Edit's save in progress (it may hold the text
    that was being saved: open it in Veranda Edit first if a text is
    missing);
  - `~VBASIC.TMP`: VeraBASIC's, the same;
  - `NAME.tmp` beside `NAME.cvt`: the Font Editor's (a `.tmp` with no
    `.cvt` beside it is not offered: it is the only copy);
  - `ASK.TMP` beside `ASK.CFG` in `/VERANDA/.SYSTEM`: Veranda Ask's (a
    lone `ASK.TMP` holds the sign-in: not offered).
  Nothing else on the card is ever deleted.

**Alt+Tab** puts Disk Tools aside at any time, even while it counts or
checks (nothing is open between two passes of the main loop). A count or
a check running then stops, because the card may change while Disk Tools
is aside, and says so when it comes back: start it again.

## Memory

At 512 KB: its two overlays (2 RAM banks) always; while working, the
walk's folder stack 2 banks, Space use's names 1, Clean up's lists 2, the
check's folder stack 2 and fault lines 1, and one bank of bits for every
65,536 clusters (a 32 GB card with 32 KB clusters: 16 banks). Without the
banks for the bits, the check still runs but does not look for crossing
chains and lost clusters, and says so.

## How

The card's sectors are read directly, through VERA's SPI port, as
CMDR-DOS's own driver reads them (`apps/sysui/sd.s`: CMD17, one sector at
a time; CMD9 for the CSD): the DOS has no block read (its `B-R` and `U1`
say "unsupported"). That file has no write command. The renaming goes to
the DOS on the kernel's command channel (`apps/sysui/dos.s`).

## Building

    make SDK=../../build/sdk          # DiskTools.cvt
    make test SDK=../../build/sdk     # the gate's test build

The gate: `tools/gate_disktools.sh` (the host folder and two SD card
images, one with faults planted; R49, 512 KB).

MIT licence (see LICENSE).
