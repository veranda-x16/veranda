# Veranda

A GEOS-style graphical desktop for the **Commander X16**, written from
scratch for the machine: 640 x 480 on VERA, banked RAM, FAT32 files on
the SD card, a dock and Alt+Tab, and an SDK for writing applications in
C or assembly.

- **Website and downloads:** https://veranda-x16.github.io
- **The manual:** the [wiki](https://github.com/veranda-x16/veranda/wiki)
  (the same pages as [docs/manual](docs/manual/Home.md); on the X16 the
  desktop's Veranda > Help)
- **Releases:** [GitHub releases](https://github.com/veranda-x16/veranda/releases).
  Each has `veranda-<version>-sdcard.zip` for a new card, and the files
  Veranda Update fetches on the X16.

Applications use the classic GEOS calls (menus, icons, dialog boxes,
GraphicsString, the r0-r15 registers), plus a modern layer on top:
16-bit coordinates for the full screen, file streams, banked memory,
fast copy and scroll. It does not run GEOS 64 binaries.

## What is in this repository

| Folder | What |
|---|---|
| `kernel/`, `api/`, `loader/` | the system: the GEOS-style kernel in RAM banks, its API table (`api/veranda.api`) |
| `shell/` | the desktop (C) |
| `apps/` | the programs and desk accessories: Paint, Colour Paint, Veranda Edit, View, Archive, Term, Veranda FTP, Gopher, Gemini, Chat, Claude, Ask, Disk Tools, About this X16, Veranda Update, FontEd, Calculator, Note Pad, Dex, Calendar, Preferences, the Photo and Text Managers, VeraBASIC |
| `sdk/` | the SDK: headers, the C library, templates, the programming guide (`sdk/docs/GUIDE.md`) |
| `docs/` | the API (`docs/API.md`), the file format (`docs/APPFORMAT.md`), the network (`docs/NET.md`), VeraBASIC, the manual, how a release is made (`docs/RELEASING.md`, `docs/PUBLISHING.md`) |
| `tools/`, `tests/` | the build tools and the gates (the automatic checks) |

Veranda Write, Veranda Calc, MOD Player, SID Player, Solitaire,
Lighthouse Pinball, Harbour Walls and geoChess are in their own
repositories of [veranda-x16](https://github.com/veranda-x16).

## Building

You need [cc65](https://github.com/cc65/cc65) (the releases are built
with commit 547d923) and Python 3 with Pillow.

    make                      # the kernel, VERANDA.PRG
    tools/mksdk.sh build/sdk  # the SDK
    tools/mkdist.sh <dest>    # the whole package for an SD card

The gates need the [x16 emulator](https://github.com/X16Community/x16-emulator)
and the R49 ROM: `EMU=... ROM=... tools/ci/gates.sh` runs the fast ones,
as the GitHub workflow does.

## Licence

MIT, Copyright (c) 2026 Marcin Spoczynski (see [LICENSE](LICENSE)).
The programs in the other repositories keep their own licences:
[docs/manual/Licences.md](docs/manual/Licences.md).
