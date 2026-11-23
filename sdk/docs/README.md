# The Veranda SDK

Applications for Veranda, the X16 desktop with the GEOS API, in C (cc65)
or assembly (ca65).

## Layout

| Folder | Contents |
|---|---|
| `include/` | `veranda.h` (C), `veranda.inc` (ca65: every call, variable and constant), `macros.inc` (`LoadW`, `MoveW` ...), `x16hw.inc` (VERA, the ROM's entry points), `vr.h` (C helpers: `vr_set_irq`, `vr_dlgbox`, `vr_tile` (an application's tile, DECISIONS V90) ...), `scrap.h` (the clipboard: the Text Scrap and the Photo Scrap), `fontpick.h` (the font picker), `vrchoose.h` (the Open and Save dialog, DECISIONS V79), `vrwin.h` (window chrome: the title band, toolbar and status bar, V79), `theme.h` (the colour theme and Veranda Look 2: `theme_load`, `theme_palette` (light or dark), `theme_rect`, `theme_menus` (the menu bar in the Veranda look and the UI font: `uiLook`, `uiFont`), `theme_look2`, DECISIONS V65, V74, V79), `vrpath.h` (the card's folders: `vr_cd` to the system, data, applications or documents folder with its fallbacks, `vr_home`: a program's first Open and Save in /DOCUMENTS; the paths themselves are veranda.h's `VR_SYSDIR` ...: DECISIONS V71), `vrnet.h` (TCP sockets through the Wi-Fi modem of TexElec's Serial & ESP32 Network Card: `net_start`, `net_open`, `net_read`, `net_write`, `net_close`, `net_poll`; `docs/NET.md`, DECISIONS V98), `vrser.h` (the serial driver under it, Veranda Term's), `vrpic.h` (a program's full-colour picture in the kernel's tile mode: `vr_pic_on`, `vr_pic_off`, `vr_pic_back`, `vr_vram_load`; tools/mkwall.py --tiles makes its records: DECISIONS V105) |
| `cfg/` | `app.cfg` (assembly), `app-c.cfg` (C), `app-c-ovl.cfg` (C with overlays that run in RAM banks, API 2) |
| `lib/` | `veranda.lib`: the C bindings (one object a call), the C start-up, the interrupt trampoline, the clipboard (`scrap.h`), the file chooser (`vrchoose.h`), the font picker (`fontpick.h`, `FontPick`: from C, or from assembly with the struct's address in a/x), the colour theme (`theme.h`), the folders (`vrpath.h`), the network (`vrnet.h`, `vrser.h`) |
| `src/` | the clipboard's C sources, the Open and Save dialog's, the window chrome's and the tile's (`vrtile.c`), for a program that compiles them into an overlay of its own |
| `tools/` | `vpack.py` (an application file), `vicon.py` (an icon), `vcard.py` (an SD card image), `vrun` (the emulator), `vram2png.py` |
| `bin/` | `VERANDA.PRG`, `VERANDA.SYS`: the system |
| `template/` | `c/` and `asm/`: copy one to start |

You need cc65 (`cl65`, `ca65`, `ld65`, `ar65`; `CC65_HOME` set), Python 3,
and x16emu with its ROM for `vrun` (`EMU`, `ROM` name them).

## Building

In a copy of a template, with `SDK` the SDK's folder (the templates
default to `../..`):

    make            # the application: "<name>.cvt"
    make run        # in the emulator
    make test       # headless: passes if the program logs its line

`app.hdr` describes the application (name, class, version, author,
description, video mode, API level; `tools/vpack.py` lists the keys) and
`icon.pbm` is its 24x21 icon. The result is a GEOS file in CVT format: put
it on the SD card (or in the emulator's HostFS folder) as it is.

## Memory

| Area | Use |
|---|---|
| `$0801-$87FF` | the application: code, data, variables (and the C stack: `$8000-$87FF` by default) |
| zero page `$02-$21` | GEOS's `r0-r15` (the kernel's calls use them) |
| zero page `$22-$4F` | the kernel's |
| zero page `$50-$7F` | the application's (`a0-a9` at `$50-$63`) |
| zero page `$80-$A8` | the X16 ROM's |
| zero page `$A9-$FF` | the application's; C programs: cc65's 26 bytes at `$A9` (`app-c-ovl.cfg`: at `$50`, leaving `$A9-$D3` to the ROM's maths library) |
| RAM banks | `BankAlloc` |

An application starts at its first byte (`$0801`) with the kernel's state
fresh (no menus or icons, the system font, the video mode of its header).
It sets itself up and returns (`rts`, or `return` from `main`): the
kernel's main loop runs it from then on through its vectors (`appMain`,
`keyVector`, `otherPressVec` ...), menus and icons.

## C

- `veranda.h` declares every call with GEOS's registers as parameters, in
  the API table's order: `WRectangle(left, top, right, bottom)`,
  `DoMenu(menu, item)`. A call that returns a register returns it (`a`,
  `x`, `r0L` ... as the table says). GEOS's variables are lvalues:
  `appMain = VR_FN(poll);`, `r0L`, `mouseXPos`.
- Tables (menus, icons, dialog boxes) are C structs or byte arrays in
  GEOS's layout; cc65 does not pad structs. A routine in a table is a C
  function `void f(void)`; the registers it gets (`r0L` for an icon's
  number ...) are read as variables.
- **Callbacks** (vectors, menu actions, icon routines, processes, dialog
  routines) are plain C functions: the kernel calls them from its main
  loop, between the application's own C code, so cc65's stack and zero
  page are theirs.
- **The interrupt:** a C function in `intTopVector` would interrupt the
  application's C code in the middle. Use `vr_set_irq(f)` (`vr.h`): it
  keeps cc65's zero page and gives `f` its own small C stack. Keep `f`
  short and call no kernel routines that draw or use files.
- `exit()` goes to the shell (`EnterDeskTop`).

## Assembly

Include `veranda.inc` and `macros.inc`, link with `cfg/app.cfg` (the first
byte of `CODE` is the start), pack with `vpack.py --load 0x0801`.
