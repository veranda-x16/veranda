# For developers

This manual is for users. If you want to write programs for Veranda,
build it, or change it, start here.

## Write programs

- **VeraBASIC** is the easiest way: a BASIC with Veranda's windows,
  menus and files. See [the VeraBASIC manual](../vbasic/manual/README.md)
  and its [tutorial](../vbasic/manual/tutorial.md).
- **The SDK** (C with cc65, or assembly):
  [sdk/docs/README.md](../../sdk/docs/README.md) and the programming
  guide [sdk/docs/GUIDE.md](../../sdk/docs/GUIDE.md).
- **The API**: every call, variable and constant in
  [docs/API.md](../API.md), generated from `api/veranda.api`.
- **The file and application format** (`.cvt` files, the info block,
  tiles, colour icons, overlays): [docs/APPFORMAT.md](../APPFORMAT.md).
- **The network** for programs (`vrnet`: TCP through the Wi-Fi modem):
  [docs/NET.md](../NET.md).
- **AI help on a program's text** (ask Veranda Ask to rewrite,
  shorten, correct, translate or summarise a text, or answer a question
  about it, with the user's own sign-in): the request files in
  [docs/AIREQ.md](../AIREQ.md).

## Build Veranda

You need cc65 and Python 3. The emulator tests need x16emu and the X16
ROM. See the repository's [README](../../README.md).

- `make` builds the kernel and the tools.
- `tools/mkdist.sh <folder>` builds the whole package for an SD card,
  with the programs from their sibling repositories when they are there.
  It also puts this manual in text form into `VERANDA/HELP`
  (`tools/mkhelp.py`).

## The gates

Every feature has an automatic test in the emulator, a **gate**:
`tools/gate_*.sh` (for example `tools/gate_shell.sh`,
`tools/gate_edit.sh`, `tools/gate_gemini.sh`). `make gates` runs the
kernel's first gates. The screenshots in this manual come from the gates
(`build/gate/*/`) and from `tools/look3_shots.sh`.

## Why things are as they are

The interface is described in [docs/API.md](../API.md) and the program
file format in [docs/APPFORMAT.md](../APPFORMAT.md); each program's
README in `apps/` and the comments in the source explain the details.
The plan of the work is [docs/PLAN.md](../PLAN.md).

## This manual

The manual's source is `docs/manual/` (GitHub Markdown, one page per
topic).

- `tools/mkhelp.py <folder>` writes it as plain text files for the X16
  (`Veranda manual*.txt`). The desktop's **Veranda > Help** opens them in
  View.
- `tools/mkwiki.sh <wiki-clone>` copies it into a clone of the GitHub
  wiki repository (`<repo>.wiki.git`), with the links and the image paths
  fixed for the wiki, and prints the git commands to publish it.
