# Veranda: plan

**Status:** plan, 2026-11-15. Nothing is built yet.
**Direction (user, 2026-11-15):** no GEOS 64 binary compatibility of any kind; a kernel written from scratch for the X16 and VERA; an SDK with C; applications come from source.

The previous project (a port of the reverse-engineered GEOS 64 KERNAL to the X16, decisions D1-D81) is at `~/Projects/geos-old`. Numbers marked *measured* come from its `docs/x16/decisions.md` (D-numbers given). Numbers marked *guess* are targets that a gate must confirm.

---

## 0. Decisions

| # | Question | Decision (user, 2026-11-15) |
|---|---|---|
| A | API | **The GEOS calls kept, modernised on top.** Classic GEOS calls keep their names, registers and table formats exactly (8-bit Y). Every call that takes a Y also gets a "wide" twin with 16-bit Y; the wide ones are the real implementation, the classic ones are thin shims. New calls for what GEOS lacks: file streams, banked memory, copy and scroll, mouse wheel and right button, video mode, palette. |
| B | Screen | **640x480, 1 bpp** (the X16's high resolution) for the shell and native applications. 640x240 and 320x240 stay as modes an application may ask for (ported GEOS sources start there: their Y fits a byte). Width, height and row stride are variables from day one. |
| C | SDK | **C (cc65) for applications**, from the first SDK release (Phase 5). The kernel itself is ca65 assembly; the SDK also ships the assembly include files. llvm-mos: not planned, not blocked. |
| E | Scope | **Phases 0-7** (user: "you can stop at 7"); the geoWrite port (phase 8) and phase 9 are not planned now. |
| D | Name, repository, licence | **Veranda** (VERA + a place to sit and work; not "GEOS"). This repository, `~/Projects/geos`, a new history. **MIT** for the kernel, SDK and tools. |

Open: whether printing matters; whether 320x240 stays once ported programs reach 640.

How A and B fit together: the 8-bit Y only hurts in a 480-line mode. A ported GEOS source starts in a 240-line mode, where its Y values cover the whole screen and nothing has to be edited. It moves to 640x480 later, call site by call site, by switching to the wide twins. Native applications use the wide calls from the start.

---

## 1. Goals and non-goals

**Goals**

1. A GEOS-style system for the stock Commander X16: `LOAD "VERANDA.PRG"` and `RUN` from the SD card, an **unmodified stock ROM**, clean return to BASIC (the old project did this on real hardware).
2. A kernel designed for the machine: banked from the first line, VERA drawing, FAT32 files, 512 KB or more of banked RAM used for data.
3. An SDK that builds C and assembly applications outside the kernel tree, with a template, a packer, a headless test run and a reference.
4. Applications from source: a new shell, a native paint program in C, C examples; geoWrite 2.1 from its reconstructed source as a separate port.

**Non-goals**

- Running C64 or GEOS 64 binaries, loader patching, profiles, a C64 screen mode.
- A custom ROM bank or cartridge (needs a ROM rebuild or hardware, gains about 6 KB of low RAM; not ruled out later).
- `.D64` images as the working file system, block-level disk calls, the 1541 BAM, REU calls, input and printer drivers.
- Multitasking. One application at a time, as in GEOS. (Since DECISIONS V83 the switcher puts whole applications aside into RAM banks and brings them back, Switcher-style, from the shell's dock: still one running at a time.)

---

## 2. The API

What stays exactly as in GEOS: r0-r15 at `$02-$21` (these are also the X16 ROM's ABI registers), the main loop with its vectors, processes and `Sleep`, menus, icons, dialog boxes, `GraphicsString`, inline calls (`i_Rectangle` ...), the maths and memory helpers, sprites, the record-file calls.

What is added:

- **Wide twins** for about 30 calls that take a Y (rectangles, lines, points, bitmaps, text, `GetString`, `PosSprite`, `IsMseInRegion`). X keeps its register; Y moves into a full 16-bit register. The exact register list is the first deliverable (Phase 0, `API.md`), generated from one table file that also produces the jump table, the include files, the C header and the reference.
- **Table formats** keep their classic layout. Each gets one flag in an unused bit that says "Y fields are words" (menus, icons, the custom position of a dialog box). Dialog items are offsets from the box, so they stay bytes. Which bits are free is checked against the classic formats in Phase 0.
- **Variables:** `mouseYPos`, `windowTop/Bottom`, `mouseTop/Bottom` become 16-bit at new addresses. The classic names stay as byte views valid in the 240-line modes.
- **New calls:** byte-stream files (open, read, write, seek, close, directory), bank memory (allocate, copy to and from a bank), `CopyRect`/`ScrollRect`, row read/write (replaces `GetScanLine`), video mode, palette, wheel and right button, key modifiers.

Dropped: `GetScanLine`, block and BAM calls, turbo, REU, `SetNewMode`/`NormalizeX` (the mode call replaces them).

Why the classic calls stay exact: the real GEOS 64 KERNAL then remains a byte-for-byte test oracle for the new code in the 320 mode (old D27: 16,000 bytes equal; that comparison found bugs no native test saw: D54, D57, D60). Cost: about 30 shims and a second field width in three table parsers; guess under 1 KB.

**C binding.** The C header and library are generated from the same API table: one small function per call that loads the registers from its arguments and calls the jump table, plus the table structures as C structs, `crt0` and a linker config. cc65's own GEOS target (installed in `~/.local/share/cc65`, zlib licence) is a guide for naming; the library is new because addresses, zero page and the file format differ. Callbacks (menu actions, icon events, processes) are C functions called through a small trampoline that saves cc65's zero page.

---

## 3. Screen modes

| Mode | Bytes per screen | Use |
|---|---|---|
| 640x480, 1 bpp, stride 80 | 38,400 | default; shell, native apps |
| 640x240 (VSCALE 64), stride 80 | 19,200 | ported sources that are 640 wide; composite monitors |
| 320x240 (HSCALE and VSCALE 64), stride 40 | 9,600 | first-day ports of GEOS 64 sources; the oracle |

The mode is a field in the application's header; the loader sets it (the mechanism of old D80, which worked). A switch is a few VERA registers and a redraw. The old engine already handled both strides (D79).

- 640x480 has 4.8 times the bytes of the old 320x200 screen. Fills and copies stay fast; text is the risk (R1).
- On composite or S-video output 480 lines are interlaced and thin horizontal lines flicker; 640x240 is the answer there.
- Colour: 1 bpp with ink and paper from the palette. 2 bpp at 640x480 is 76,800 bytes: no back screen and half the drawing speed; rejected. Later option, not verified: a tile layer under the transparent paper pixels for a paper colour per 8x8 cell.

---

## 4. Architecture

### 4.1 Principles, each from a measured lesson

1. **Banked by design, not by a tool afterwards.** The old project retrofitted banks onto flat code (D45/D46) and then found, one crash at a time: data read across banks (D46, D60), callbacks into the application from a bank (D62, D66), `Sleep` storing glue frames (D78), `FillRam` and `ReadFile` writing the application's `$A000-$BFFF` into kernel code (D69, D73). Here these are written rules (4.4).
2. **Fixed RAM gets a real budget.** The old fixed core was 2,984 bytes and ended with about 130 free. New budget: 5.9 KB.
3. **Hot paths do not cross banks.** A crossing cost 248 cycles, 263 with the ROM bank handling (D48, D59); banking slowed text from 762 to 820-851 ms per 1,000 characters. Graphics, text and the system font live in one bank.
4. **VERA seeks are expensive, streaming is cheap.** The unrolled fill writes a byte in 4 cycles (D31); the general engine once cost about 800 cycles per glyph row. Everything is built from long spans.

### 4.2 Low memory

| Range | Use |
|---|---|
| `$0000-$0001` | RAM bank, ROM bank (ROM bank 0 while Veranda runs) |
| `$0002-$0021` | r0-r15 |
| `$0022-$004F` | kernel zero page (46 bytes) |
| `$0050-$007F` | application zero page (48 bytes; a0-a9 first) |
| `$0080-$00A8` | X16 ROM: KERNAL `$80-$90`, DOS `$91-$9B`, reserved, audio (`x16-rom/cfg/x16.cfginc`). **Never touched, so no zero-page swap** (old D72 not needed). |
| `$00A9-$00FF` | application zero page (87 bytes): the ROM's BASIC and maths area, free because Veranda uses neither. cc65's zero page goes here. |
| `$0200-$03FF` | X16 ROM variables, vectors, interrupt stub at `$038B`. Only `$0314` and `$032E` are hooked, and restored on exit. |
| `$0400-$07FF` | OS variables at stable public addresses |
| `$0801-$87FF` | **application RAM, 32.7 KB** |
| `$8800-$9EFF` | resident core, 5.9 KB (4.3) |
| `$A000-$BFFF` | bank window: kernel banks, or the application's own banks |

Sizes are budgets; they are fixed after Phase 2 and part of the ABI from then on. cc65 needs 26 zero-page bytes by default (`zeropage.inc`): they fit in `$A9-$FF` with room for the application.

### 4.3 Resident core (`$8800-$9EFF`)

Jump table; bank gates; interrupt entry; the inline-call helpers (they read the caller's return address); `Sleep`; `CallRoutine` and the C callback trampoline; every routine that may touch the application's `$A000-$BFFF` (`MoveData`, `FillRam`, far copy, file read and write loops); ROM call wrappers and the file name buffer (the ROM reads names with bank 0 mapped, D46); bit-mask tables.

### 4.4 Kernel banks and calls across them

Six banks at the top of RAM (found with `MEMTOP`, then `MEMTOP` lowered): **G** graphics, text, system font; **G2** bitmaps, `GraphicsString`, sprites, classic shims; **U** menus, icons, dialogs, text input; **F** files; **S** start-up, loader, time, mode; one spare. The old kernel was 20.3 KB in four banks; guess for the new one: 30-35 KB. (Built: seven banks, P printing since V38, and since V50 a pristine copy of them in the seven RAM banks under them, for the panic box; since V64 the bank under those, RB, gets the resident core's copy when Veranda goes to BASIC and stays; T fonts since V62; W, the switcher and the RAM banks, since V83: nine; C, the canvas and ToBASIC, since V165: ten, C the last and without a copy.)

Rules, checked by a link-time linter:

- Each bank is linked separately against the resident symbols. A call to another bank is written as a far call; nothing else links.
- A bank never reads another bank's data. Shared data is resident or in `$0400`.
- A pointer passed to the kernel points below `$A000`. Far variants take bank plus address and run in the resident core.
- Every call from a bank into application code goes through one resident dispatcher (old D66).
- The gate saves the caller's RAM bank on the stack and restores it, so an application may run code or keep data in its own banks.

Gate cost: the old glue preserved A, X, Y and P both ways under `SEI`. New rule for wide calls: flags are not inputs; results come back in A, X, Y and carry. Target: at most 120 cycles per crossing (*guess*; measured in Phase 1). Classic calls that take flags (`DrawLine`) get a shim that stores them first.

### 4.5 Interrupts and the ROM

Kept from what worked:

- Hook `$0314`, call the stock handler through a fake interrupt frame (D22): PS/2, mouse, clock and the VSYNC acknowledge. Save and restore VERA `CTRL`, `ADDR0`, `ADDR1` around everything, and the FX state if FX is used.
- Keyboard: `GETIN` from the main loop in ISO mode (D23, D32), Alt through `$032E` (D33).
- Mouse: `mouse_get` as a source of movement, own pointer position, wide range and re-centring (D34, D68: found on real hardware). New: wheel and right button.
- Clock: `clock_get_date_time`. Files: `OPEN`, `MACPTR`, `MCIOUT`, the `P` seek. Exit: `enter_basic` after restoring vectors, palette, sprites, `screen_mode`, ISO off (D25).
- Not used: the ROM's `GRAPH_*`/`FB_*`, BASIC, the maths library.

### 4.6 Start-up and loading applications

- `VERANDA.PRG`: a small BASIC stub, the resident core and a loader. It loads `VERANDA.SYS` (the bank images) into the kernel banks with `LOAD`, which fills banked RAM and wraps banks by itself.
- Then the first auto-exec file, else the shell.
- An application is one file (section 6) with a header that names load address, start address, video mode, API level. The loader refuses a higher API level than the kernel's.
- **Overlays:** a record-structured application is read into RAM banks once, at start. Switching an overlay is a copy from a bank into application RAM (4,000 bytes; guess 6 ms) instead of a disk read.
- **Desk accessories and returning to the shell:** the running application's RAM is copied to a bank and back. Phase 9.
- **BASIC and back (built, DECISIONS V64, the RBOOT model after GEOS's RBOOT):** `ToBASIC` with `r1 = TOBASIC_KEEP` (the shell's *BASIC (keep Veranda)*) fills one more bank, RB, under the kernel banks' copy: the resident core as it is then, the code that puts it back, a descriptor with CRCs; it leaves that, the kernel banks, their copy and the resident core above MEMTOP (`$8800`, the bank count RB) with the ROM's vectors, screen and mouse back; `SYS 35328` (ReEntry, 96 bytes that ToBASIC writes over the second jump table at `$8A00`) or `RBOOT` (a small file in the system folder that finds RB by its signature) checks the copies, puts the resident core and the kernel banks back and goes to the desktop in the shell's folder, without the card; a damaged copy: a message, and `RBOOT` loads `VERANDA.PRG` from the card. Without it (*Quit Veranda*) `ToBASIC` frees everything.

---

## 5. Graphics on VERA

### 5.1 VRAM (640x480, 1 bpp)

| Range | Bytes | Use |
|---|---|---|
| `$00000-$095FF` | 38,400 | foreground (layer 1, bitmap) |
| `$09600-$12BFF` | 38,400 | back screen |
| `$12C00-$16BFF` | 16,384 | save-under stack for menus and dialogs (the shell's tile desktop, DECISIONS V101: `$12C00` the program's palette rows 2-15, `$13000-$16BFF` 480 tiles; the stack is not used then) |
| `$16C00-$1ABFF` | 16,384 | sprite pictures, 8 slots of 2 KB (as D28) |
| `$1AC00-$1EFFF` | 17,408 | free: application off-screen area, later the colour map (V30; in tile mode V101's 4 bpp map, its off-screen columns the covered cards' shadow bytes, `$1EB00` the count of covers) |
| `$1F000` and up | | X16 character set, PSG, palette, sprite attributes: not touched except palette entries and sprites, which are restored on exit |

All bases are multiples of 4 (needed for FX cache writes).

In the 320 x 240 mode's canvas (DECISIONS V166, a program's picture of one byte a pixel, `kernel/c/canvas.s`):

| Range | Bytes | Use |
|---|---|---|
| `$00000-$0257F` | 9,600 | the 1 bpp screen (layer 1) |
| `$02800-$153FF` | 76,800 | the picture, an 8 bpp bitmap (layer 0, L0_TILEBASE `$14`): over the back screen and the usual save-under room |
| `$15400-$155DF` | 480 | palette entries 16-255 as they were (ColorOff puts them back) |
| `$16C00-$17BFF` | 4,096 | sprite slots 0 and 1 |
| `$1AC00-$1EBFF` | 16,384 | the save-under stack (the colour map's room: no colour map in canvas mode) |

### 5.2 The span engine

From the old `fb.s` (this project's own code, rewritten): one span of bytes on one scanline, first byte / middle / last byte with keep masks, one tight loop per operation for the middle, port 1 reads and port 0 writes, foreground and back screen selected by `dispBufferOn`. Here: 16-bit row, stride as a variable, a 480-entry row table in bank G.

### 5.3 Back screen, menus and dialogs

- The back screen stays a real bitmap, and `dispBufferOn`, `RecoverRectangle`, `ImprintRectangle` keep their GEOS meaning.
- **Menus and dialog boxes do not depend on it.** Opening one copies the covered area into the save-under stack; closing copies it back. The default for applications becomes "draw to the foreground only", which halves the drawing work. 16 KB holds 400x320 pixels; a larger box falls back to `RecoverRectangle` or the application's `RecoverVector`.
- A second VERA layer for dialogs was rejected: a 1 bpp layer cannot show opaque paper (pixel 0 is transparent), and a 2 bpp layer costs 76,800 bytes.

### 5.4 VERA features used

- **Both data ports:** VRAM to VRAM copy is `lda DATA1 / sta DATA0`, 8 cycles a byte; a full-screen copy is about 38 ms (computed). `CopyRect` and `ScrollRect` are kernel calls.
- **No hardware scrolling** for bitmap layers (VERA reference); scrolling is the copy above.
- **FX 32-bit cache writes** for fills, one write stores four bytes: a full-screen clear from about 19 ms to about 6 ms (*guess*). Needs VERA firmware 0.3.1 or later; the kernel reads the version (`DCSEL=63`) and falls back. Optional, after the plain engine passes.
- **FX line and polygon helpers: not usable** (2, 4 and 8 bpp only).
- **Sprites:** pointer on sprite 0 (with an outline colour), text cursor on sprite 1, sprites 2-7 for applications (GEOS 1 bpp pictures converted to 4 bpp when changed, D28); native VERA sprite calls too.

### 5.5 Text

Measured on the old port: 762 ms per 1,000 characters (D30), about 60 % in the font code. At that speed an 80x60 screen of text takes 3.6 s: too slow.

Design: render a run of characters into a 1 bpp strip in RAM (width of the run by the font height), apply the styles on the strip, then send each strip row to VERA as one span: one seek per row of the run instead of one per glyph row. Target: 250 µs per character for the plain system font (*guess*; gated in Phase 2). Character widths and style rules equal GEOS's (ported page layouts depend on them).

Fonts are GEOS format. Veranda ships its own system font with the same metrics as GEOS's BSW 9 (the BSW font is used only as a test fixture for the oracle). Fonts in other banks (R6): done, DECISIONS V62: the font service in kernel bank T keeps GEOS font files in RAM banks for every program; text reads a banked font's glyph rows through a resident row copy (the system font's path unchanged, 249 us a character; a banked font 10-20 % slower than the same font in the program's memory).

---

## 6. Files

**FAT32 through CMDR-DOS, no disk images.** Directories, long names, no 170 KB limit, files the user can copy on a PC.

- **A GEOS file is one FAT32 file in CVT format**, the standard exchange format for GEOS files: directory entry, info block (icon, class, author, type, addresses, description), and for record files the record table and the records. Existing GEOS fonts and documents in `.cvt` form work as they are.
- **Other files** (text, pictures, `.PRG`) appear with a generic icon and are read and written through the stream calls.
- **Record files (VLIR) live in banked RAM while open.** `OpenRecordFile` reads the whole file into banks; record calls work on memory; the file is written back whole to a temporary name and renamed (FAT32 cannot insert in the middle of a file; a whole-file write is always a valid CVT file). Write back on `CloseRecordFile` if changed; measured in Phase 5. Fallback: in-place updates with `,M` mode (not verified that it extends files).
- **Classic file calls kept:** `GetFile`, `FindFile`, `FindFTypes`, `GetFHdrInfo`, `SaveFile`, `DeleteFile`, `RenameFile`, the record calls, `CalcBlksFree` (from the DOS free space). `FindFTypes` needs each file's header, so the kernel keeps an index of the current directory in a bank.
- **Calls that take track and sector are gone.**
- **Speed reference:** the old image driver read a 256-byte block in 2.32 ms and wrote one in 4.85 ms (D38); sequential `MACPTR` should be faster; measured in Phase 5.
- **Import:** a host tool converts GEOS files from `.D64` images to CVT.

---

## 7. The SDK

```
sdk/
  include/   veranda.h (C)   veranda.inc (assembly: wide API, constants)
             classic.inc (GEOS names)   macros.inc   x16.inc
  cfg/       app.cfg   app-c.cfg   app-overlay.cfg   deskacc.cfg
  lib/       crt0.o   veranda.lib (C bindings, callback trampoline)
  tools/     vpack (header text + icon + binaries -> CVT file)
             vicon (PBM/PNG -> icon)   vcard (SD image or folder)
             vrun (x16emu with the folder as HostFS)   vtrace   vram2png
  template/  c/ (Makefile, main.c, app.hdr, icon.pbm)   asm/ (the same in ca65)
  examples/  hello, menus, dialog, files, sprites, scroll, paint (C), asm-hello
  docs/      reference generated from the API table, plus a guide
```

- `make` builds the application, `make run` starts it in the emulator, `make test` runs it headless.
- Test support is the same as for the kernel: a log call writes to the emulator console (`$9FBB`), an exit call dumps VRAM and quits (`$9FB4`), a scripted pointer and key source plays a session (the method of old D35 and D64).
- Debugging: `vtrace` (the old `x16trace.py` with a bank-aware symbol map: last N instructions before a BRK); a kernel build that logs every bank crossing; a panic screen with PC and bank; `-wuninit` runs.
- The SDK is installed outside the kernel tree, and a gate builds both templates against the installed copy, so the kernel cannot leak private symbols into applications.
- The API table file is the single source for the jump table, `veranda.inc`, `classic.inc`, `veranda.h`, the C library and the reference pages.

---

## 8. Reuse and licences

The old project's KERNAL sources (`kernal/` except `kernal/x16/`, `drv/drv1541*`, `inc/`) are Berkeley Softworks' program in reconstructed form, not freely licensed; geoWrite and the BSW fonts likewise. None of that goes into Veranda. What the old project wrote for the X16 itself (`kernal/x16/`, the X16 half of `drv/drvx16img.s`, the tools and tests) is this project's own work and may be reused. Veranda is not a clean-room implementation (the old sources have been read); the API (names, registers, table layouts) is documented in published GEOS programmer's references. The user weighs that risk (R7).

| Reuse | From `~/Projects/geos-old` | Note |
|---|---|---|
| Span engine | `kernal/x16/fb.s` | generalise (5.2) |
| Sprite conversion and sync | `kernal/x16/sprites.s` | drop the VIC shadow |
| IRQ chain, mouse, keyboard, clock, exit | `kernal/x16/irq.s`, `mouse.s`, `keyboard.s`, `rtc.s`, `tobasic.s` | proven on hardware |
| CMDR-DOS open, seek, `MACPTR`/`MCIOUT` | the X16 half of `drv/drvx16img.s` | |
| Gate harness | `tools/x16/gate.sh`, `tests/x16/check_*.py`, `docs/x16/environment.md` | |
| Oracle | `tools/x16/sim6502.py`, `geos64sim.py`, `tests/x16/gfx_scene.s`, `c64sessions.py` | stays in geos-old; gates call it through `GEOS64_REF=~/Projects/geos-old` and report SKIP (never PASS) without it |
| Host tools | `fat32.py` (needs subdirectories and long names), `vram2pbm.py`, `cvt.py`, `d64.py`, `x16trace.py`, `build_trace_emu.sh` | |
| Shell design | `apps/x16/desktop.s` | rewritten for directories, in C |
| Not reused | `banks.py`, `glue.s`, `zpswap.s`, everything `c64*`, profiles | |

---

## 9. Phases and gates

Every gate runs x16emu headless against the stock ROM. Sizes: S about 500 lines, M about 1,500, L 3,000 or more (new code, guesses).

| Phase | Content | Gate (automatic unless noted) | Size |
|---|---|---|---|
| **0 Spec** | API table with registers for every call; memory map constants; generators for includes and the C header; gate harness | `spec`: the table generates `veranda.inc`, `classic.inc` and `veranda.h`, which assemble and compile; no two entries share an address; classic table flags checked against the GEOS formats | S |
| **1 Boot and drawing** | `VERANDA.PRG` + `VERANDA.SYS`, resident core, bank gate, span engine at 640x480, wide rectangle, line, point, pattern, `CopyRect`; exit to BASIC | `boot`: starts, draws, returns, BASIC answers `PRINT 6*7`. `gfx1`: a shape drawn at y and at y+N gives the same rows N lower; golden picture confirmed once by the user; timings: full-screen fill, full-screen copy, bank crossing at most 120 cycles | M |
| **2 Text, classic calls, modes** | Strip text renderer, system font, styles; classic shims; 320x240 and 640x240 | `gfx`: the old `gfx_scene.s` in 320 mode equals the GEOS 64 KERNAL byte for byte; each wide call below line 256 equals its classic twin; text at most 250 µs per character | M |
| **3 Input and main loop** | IRQ, pointer, keyboard, processes, `Sleep`, sprites, clock | `input`: scripted session log equals the expected log twice; 20 scenes drawn with a moving pointer still equal the reference, and removing the IRQ's VERA restore makes it fail (D36) | M |
| **4 User interface** | Menus, icons, dialogs, `GetString`, save-under | `ui`: sessions on classic tables equal GEOS 64's screens in 320 mode; 640x480 goldens; kernel bank images unchanged after each session (D66) | M-L |
| **5 Files, loader, SDK v1** | Streams, CVT files, directory index, record files in banks, loader, overlays; C bindings, `crt0`, callback trampoline; `vpack`, `vcard`, both templates | `disk`: on HostFS and on an SD image: write, read back, rename, delete, record insert and delete, host-side check of every file and of the FAT; timings. `sdk`: the C and assembly templates build against the installed SDK and run; a C program with a menu and a dialog runs a scripted session | L |
| **6 Shell (C)** | Directory window, icons, open, copy, delete, rename, mode setting | `shell`: scripted session opens two applications and returns. **Then a run on the real X16** (manual) | M |
| **7 Paint (C)** | A native paint program at 640x480 | `paint`: session draws, saves, reloads, picture equal | M |
| **8 geoWrite port** | Separate directory with its own notice: 8a as it is in 320x240, overlays from banks; 8b screen-memory code replaced by `CopyRect` and row calls; 8c 640 wide; 8d 480 lines | 8a: the old `gwrite` session: screen after typing equals the original on GEOS 64 byte for byte; the saved document equals GEOS 64's as CVT. 8b-8d: goldens and document equality | L |
| **9 Later** | Desk accessories and application swap, FX fills, colour map, reference guide, printing as file export, printing to PDF (DECISIONS V38: chosen over printer drivers) | one gate each | - |

Something visible exists after Phase 1; the SDK is usable after Phase 5; a usable system after Phase 6.

---

## 10. Risks and open questions

| # | Risk | Answer |
|---|---|---|
| R1 | Text too slow at 640x480 (the old speed gives 3.6 s for a full screen) | Strip renderer; the 250 µs target is gated in Phase 2. If missed: 640x240 becomes the default |
| R2 | Two sets of drawing calls confuse or bloat | Shims only; one implementation. If over 1.5 KB, move the shims into the SDK library |
| R3 | Whole-file write-back of record files is slow or loses data on a crash | Measured in Phase 5; fallback in section 6 |
| R4 | CMDR-DOS differences between HostFS and a real card; ROMs up to R48 corrupt cards when appending to (or opening `,M`) an empty file; R49's MCIOUT garbles an overwrite that crosses a 512-byte sector (DECISIONS V55) | Every disk gate runs on both; no append mode; a minimum ROM version is checked at start; `'m'` and seeked streams are written by CHROUT (V55) |
| R5 | Emulator passes, hardware fails (old D68 found three such bugs) | A hardware run closes Phases 1, 3, 6 and 7 |
| R6 | Fonts and large data in banks cannot be read while a kernel bank is mapped | v1: fonts in application RAM; closed by V62: each glyph row copied through the resident core (`FontRow`), the index table into bank G (`IDX_COPY`) |
| R7 | Licence: not clean-room; geoWrite and BSW fonts cannot be relicensed | Section 8; ports kept apart |
| R8 | Application RAM (32.7 KB) is tight for C programs and geoWrite | Overlays and data in banks; cc65 code is larger than assembly, so C programs get the overlay config from the start |
| R9 | Not verified: free bits in the classic table formats; `M` mode extending a file; the paper-colour layer; the FX gain; all cycle and size guesses | Each has a named phase where it is measured |
| R10 | Scope: a kernel, a file layer, a shell, an SDK and ports | Phases 0-6 are the product; 7 and 8 prove it; 9 is optional |
