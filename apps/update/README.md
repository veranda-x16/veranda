# Veranda Update

Brings the Veranda installation on the SD card up to date online
(DECISIONS V130): from the GitHub releases of Veranda's public repository,
or from your own builds on a PC on your home network. Through TexElec's
Serial & ESP32 Network Card (Zimodem), as Veranda Gemini and Claude.

## Using it

- **Check** (C) fetches the list of files of the newest build,
  `UPDATE.LST`, and compares the card with it, file by file: a file that
  is missing is *new*, one of another size or another CRC-32 is
  *changed*. The window shows the build installed (the card's
  `/VERANDA/UPDATE.LST`) and the one available, what's new, and every
  changed and new file with its size; "Up to date" when there is nothing
  to fetch.
- **Update** (U) fetches them, each to `/VERANDA/.SYSTEM/UPD/` with its
  CRC-32 computed as it comes and checked with its size. Only when every
  file has come and passed are the card's files replaced: the card's
  version of each moved to `/VERANDA/.SYSTEM/OLD/<the build replaced>/`,
  the new one put in its place, Veranda's system files (VERANDA.PRG,
  AUTOBOOT.X16, VERANDA.SYS, RBOOT, SHELL.cvt) last, then the list
  itself. When a system file changed: **Restart to finish** (Veranda
  quits to BASIC, which types `BOOT` in `/VERANDA`).
  - A dropped connection, Esc, a file that fails its CRC-32 check or one
    the release does not have: the update stops and the card is as it
    was. **Update again goes on** where it stopped: the files that came
    whole are kept (by their CRC-32) and not fetched again.
  - Alt+Tab puts it aside at any time; a file being fetched then is
    fetched again from its start when it is back. The swap itself runs
    in one go, so it cannot be put aside half done; if the power goes in
    the middle of it, Veranda Update finishes it at its next start.
- **Undo last update** puts back what the last update replaced (and
  removes what it added). One undo is kept: the backup of the update
  before is deleted when a new one is made.
- **Source...**: GitHub releases (`owner/repo`, `veranda-x16/veranda` at
  first; a saved `sandlbn/veranda-x16`, the repository before the organisation, is read
  as `veranda-x16/veranda`: DECISIONS V139) or a PC on my network (`host:port`). Kept in
  `/VERANDA/.SYSTEM/UPDATE.CFG` (`source=github` or `pc`, `repo=`,
  `pc=`, `channel=`).
- **The channel** (GitHub only; Source... asks "Stable releases?",
  Cancel: Test): **Stable** reads the release GitHub marks latest
  (`releases/latest/download/UPDATE.LST`); **Test** the one release
  tagged `test`, a pre-release whose assets each test build replaces
  (`releases/download/test/UPDATE.LST`). Never GitHub's JSON API: the
  same addresses, redirects and code as Stable (docs/RELEASING.md).
- **The version:** a list with a `version 1.0` line shows "Veranda
  1.0, build ..." for Installed and Available.

- **Dictionaries** (D; V198): Veranda Write's spelling dictionaries
  are not in Veranda's releases nor its package. They are the assets of
  the release `dict-1` of `veranda-x16/veranda-write` (made by that
  repository's `tools/mkdict.py`; the tag is the dictionaries' format,
  so a later format gets another tag and an older Write never fetches
  one it cannot read), with their list `DICT.LST` in `UPDATE.LST`'s
  format, every file under `VERANDA/DICT/` (a list naming anything else
  is refused). Dictionaries fetches that list from
  `https://github.com/veranda-x16/veranda-write/releases/download/dict-1/DICT.LST`
  (always GitHub, whatever Source... says) and compares the card;
  Update then asks for each dictionary with something to fetch
  ("English", "Polish": a file's name before its first dot, so EN.DIC
  goes with its licence EN.DIC.txt), checks that the card has the room
  (what is to come and 64 KB more, by `CalcBlksFree`), and fetches and
  swaps them as any update (CRC-32, UPD, the swap). Their backup is
  `/VERANDA/.SYSTEM/OLD/dict-1/`, apart from the builds'; the card's
  `VERANDA/UPDATE.LST` does not change. Undo removes them (one undo is
  kept, as ever). Check never offers them.
- **A program's request** (V198): `/VERANDA/.SYSTEM/UPDATE.REQ`, read
  and deleted at the start: the line `dict` runs Dictionaries at once;
  `back <name>`: Quit brings that program back if it is aside (its task
  name, the name it was started by). Veranda Write's Tools > Get
  dictionaries writes it, and the desktop's `START.REQ` (the shell
  starts the program it names: shell/prg.c) to start Veranda Update.

**What it never touches:** `/DOCUMENTS` (the example programs a package
has are in its list as `doc-sample`, and never written), the settings in
`/VERANDA/.SYSTEM` (`*.CFG`, the chats, bookmarks, notes, preferences),
and any file the list does not name. A file no longer in the list is not
deleted. A list that names anything else (a path outside `VERANDA/`,
`PC/` and `DOCUMENTS/`, a folder starting with a dot, `..`, a `*.CFG`) is
refused whole.

**Security:** the modem makes the TLS connection to GitHub (Zimodem's
`ATCS`) and does **not** check the certificate. What protects the card
from a damaged file is the CRC-32 of each file in the list, which came
over the same connection: it catches a cut or garbled transfer, not a
forged one. The PC source is plain HTTP on your own network.

## The two sources

**GitHub releases.** `https://github.com/<repo>/releases/latest/download/UPDATE.LST`
answers 302 with a signed address on another host
(`release-assets.githubusercontent.com` or `objects.githubusercontent.com`,
some 600-1,000 bytes); Veranda Update follows it with a new connection
(every redirect: another `ATCS`), and then fetches each file from the
release's tag, `/releases/download/<tag>/<asset>`, the same way. Only
Veranda and the author's own MIT programs are published there: the
personal-use ports (geoWrite, TopDesk, geoChess) never are, and the
programs whose licences are not settled (MOD Player, Solitaire) are left
out for now.

**The pack (V210).** A release also has `<crc32>.pak`: every file of it
deflated, one after another (its list's `pack` line, and a `z <offset>
<zsize>` line after each file). Veranda Update asks GitHub for the pack's
address once (one 302: its 5.7 KB of headers once, not for every file),
keeps the asset host's connection open (`Connection: keep-alive`: one
TLS connection, not one for every file), fetches each file's part with
an HTTP `Range`, and inflates it as it comes (`inflate.s`, the window in
VRAM's back screen); each file's size and CRC-32 are checked as before.
About half the bytes come over the modem. GitHub's signed address lasts
5 minutes: it is asked for again after 4, or when the asset host refuses
it. When the pack does not give a file whole, that file and the rest come
from their own assets, as before V210. A release without a pack (before
V210), the PC source and the dictionaries are fetched file by file.

**A PC on your network.** For your own builds, ports and all. Copy
`PC/update_server.py` from the card (or `tools/update_server.py` from
the source) to a PC with a package folder (`tools/mkdist.sh` makes one)
and run (Python 3, nothing to install):

    python3 update_server.py ~/Projects/veranda-dist/pkg-<hash>

It prints the PC's address; in Veranda Update choose Source..., Cancel
(a PC on my network), and type it with the port (8644), e.g.
`192.168.1.20:8644`. Only private addresses may connect; never open its
port to the Internet.

## Publishing a release (on the PC, by you)

The whole release, gates to package, is one command now:
`tools/release.sh <version>` (docs/RELEASING.md), and `tools/publish.sh
<version>` pushes it to the organisation, whose release workflow builds
the GitHub release from the source (docs/PUBLISHING.md). The steps below
are what the GitHub release is, by hand.

Nothing here publishes anything: `tools/mkrelease.sh` makes the release's
files and prints the command; you run it. `CHANNEL=test` makes a build
for the Test channel (the tag `test`, a pre-release, its assets replaced).

1. Build the package: `tools/mkdist.sh ~/Projects/veranda-dist/pkg-<hash>`
   (it writes `VERANDA/UPDATE.LST`; `NOTES=whatsnew.txt` gives its "what's
   new" text, else the last commit's subject's first sentence).
2. Make the release's files:
   `tools/mkrelease.sh ~/Projects/veranda-dist/pkg-<hash> ~/Projects/veranda-dist/rel-<hash>`.
   It keeps only the files `tools/release.allow` names (and refuses a
   port even if it were named there), writes `UPDATE.LST` with the
   release's tag, one asset `<crc32>.bin` for each distinct file (the
   bytes as they are: an older Veranda Update fetches each whole), the
   pack `<crc32>.pak` (V210: the same files deflated; `--no-pack`: none),
   `NOTES.md`, and prints what it left out.
3. Make sure your public repository (`~/Projects/veranda-x16`) has the
   source of that build pushed, then run the `gh release create ...`
   command it printed (signed in with `gh auth login`). The release is
   marked latest; Veranda Update's Check sees it at once.

Since V139 the organisation's release workflow does steps 1-3 from the
source (`tools/ci/build.sh`, tag `v<version>`). A release can be deleted with
`gh release delete <tag> --repo <owner/repo>`; the X16 then sees the
previous latest one.

## The list: UPDATE.LST

Plain text (`tools/mkmanifest.py`):

    VERANDA-UPDATE 1
    build cf42c0f 2026-11-21
    version 1.0                             (Veranda's version: VERSION)
    tag v1.0                                (a release's)
    note What's new, up to 8 lines of 76 characters
    pack 5e6f7a8b.pak 1384720               (a release's, V210)
    file 6203 1a2b3c4d system - 1a2b3c4d.bin VERANDA/VERANDA.PRG
    z 0 4127                                (V210: its part of the pack)
    ...
    end 61

`file <size> <crc32> <kind> <min> <asset> <path>`: kind `system`, `app`,
`font`, `help`, `wallpaper`, `pc` or `doc-sample`; min the oldest build
date the file may go over (`-`: any); the asset is named by the CRC-32
(files of the same bytes share one); the path from the card's top. A
list without its `end` line was cut short and is refused. A Veranda
Update from before V210 skips the `pack` and `z` lines (words it does not
know).

## Building

    make SDK=../../build/sdk           # Update.cvt
    make test SDK=../../build/sdk      # the test build (gate update)

Main RAM holds `main.c` (the menus, the overlays' wrappers, the pack's
`sink_z`), `http.c` (HTTP/1.1 on vrnet: redirects, Content-Length,
chunked; V210: Range, keep-alive), `crc.s` (CRC-32, table-driven, about
50 cycles a byte; its table in a RAM bank), vrnet (with `vrahead.c`: one
XON ahead) and sysui; overlay 1 (appBank) `job.c` (Check, Update);
overlay 2 `man.c` and `ui.c` (the list, the window, the settings since
V198); overlay 3 `swap.c` (the card's files, the swap, Undo, a request);
overlay 4 (V210) `inflate.s` and `pick.c` (the dictionaries to get, the
card's room). The C stack is 512 bytes (V210; gate update measures its
deepest at under 100). RAM banks: the overlays' 4, 4 of its own (the
list's 2, a text's, the CRC table's), vrnet's 2 while the modem is on;
VRAM's back screen ($09600-$12BFF) for inflate's window and code lengths.
Its gate: `tools/gate_update.sh` (`ONLY=timing`: only its timing
sessions, a release without a pack and one with).

MIT licence (see LICENSE).
