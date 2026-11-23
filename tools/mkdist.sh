#!/bin/bash
# The Veranda package for an SD card, in the card's layout (DECISIONS V71).
#
#   tools/mkdist.sh <dest>
#
# <dest> gets what goes on the card's top level:
#   VERANDA/            VERANDA.PRG, AUTOBOOT.X16 (the same file: BOOT in
#                       this folder starts Veranda), VERANDA.SYS, RBOOT,
#                       SHELL.cvt, Veranda Setup.cvt, README.txt,
#                       UPDATE.LST (Veranda Update's list of the package's
#                       files: tools/mkmanifest.py, written last; V130)
#   VERANDA/APPS/       the applications and desk accessories (and Wikipedia.cvt,
#                       Veranda Gemini's Wikipedia launcher: V128)
#   VERANDA/FONTS/      Gate Sans, Gate Mono 10 and 12 (Veranda's own, tools/fontcvt.py, tools/gatemono.py)
#   VERANDA/WALLPAPERS/ Dusk.cvt (tools/mkwall.py --dusk; DECISIONS V78; full
#                       colour tiles since V101; drawn as tiles since V175,
#                       tools/wall_dusk.py), Still Water.cvt, Low Hills.cvt
#                       and Sunroom Tiles.cvt (V162: tools/wall_stillwater.py,
#                       wall_hills.py, wall_tiles.py, drawn as tiles; the Meadow
#                       no longer shipped)
#   VERANDA/HELP/       VeraBASIC's help (VR_HELPDIR, DECISIONS V93), the
#                       manual in help form, the reference card's PDF (V99);
#                       Veranda's manual as text (Veranda manual*.txt: the
#                       shell's Veranda > Help, tools/mkhelp.py, V134)
#   PC/                 claude_bridge.py: Veranda Claude's bridge to Claude
#                       Code, run on a PC, not on the X16 (DECISIONS V115);
#                       chatgpt_signin.py: Veranda Ask's sign-in helper
#                       (Sign in with ChatGPT from a PC's browser, V116);
#                       web_proxy.py: Veranda Gemini's private web proxy
#                       (web pages as gemtext, V124);
#                       update_server.py: Veranda Update's PC source (this
#                       package served to the X16 on the home network, V130)
#   DOCUMENTS/          the user's files: VeraBASIC Examples/ (the example
#                       programs and the tutorial's steps), Garden.brd (Bird
#                       Watch's document; Bird Watch, a made application,
#                       is in VERANDA/APPS: V99)
# No .SYSTEM: the shell makes it, and Veranda Setup, which moves a card of
# the layout before into this one, runs once on it (its LAYOUT.LOG there).
#
# Built from this tree (the kernel, the SDK into <dest>/../ a work folder,
# the shell, Setup, the applications) and from the sibling repositories,
# each exported from a branch with git archive (their working trees are
# left as they are), built against this tree's SDK:
#   GEOWRITE  dropped from the package (2026-11-21; Veranda Write opens
#             geoWrite documents); GEOWRITE=<tree> puts it back
#   CALC      ~/Projects/commander-calc    ref layout (else veranda)
#   GEOCHESS  ~/Projects/veranda-geochess  ref veranda
#   TOPDESK   dropped from the package (2026-11-21); TOPDESK=<tree> puts it back
#   X16MOD    ~/Projects/x16-mod           ref layout (else veranda)
#   SOLITAIRE ~/Projects/veranda-solitaire ref main
#   CWRITE    ~/Projects/commander-write   ref main
#   PINBALL   ~/Projects/veranda-pinball   ref master    Lighthouse Pinball
#   HWALLS    ~/Projects/harbour-walls     ref master    Harbour Walls
#   SIDPLAY   ~/Projects/veranda-sidplay   ref main      SID Player
# (each: <NAME>=<tree>, <NAME>_REF=<ref>; a missing tree is left out with a
# warning). No test builds, scripts or fixtures go in.
#
# Inside the veranda-x16 repository (this tree is its veranda/, and ../apps
# holds the applications) the applications are built from ../apps/* instead
# (each copied into the work folder, without its build/), and the
# personal-use ports (geoWrite, geoChess, TopDesk) are not looked for:
#   apps/calc  apps/modplayer  apps/solitaire  apps/pinball
#   apps/harbour-walls  apps/sidplay  (apps/commander-write when it is there)
# MKDIST_SIBLINGS=1 forces the sibling repositories even there. (This file
# is the same in both trees: tools/release.sh's patch takes it whole.)
#
# The version (docs/RELEASING.md): the file VERSION at the top, or
# VERANDA_VERSION=1.0; it goes into the README's first line and
# UPDATE.LST's "version" line.
set -e
cd "$(dirname "$0")/.."
TOP=$PWD
[ -n "$1" ] || { echo "usage: tools/mkdist.sh <dest>" >&2; exit 2; }
mkdir -p "$1"
DEST=$(cd "$1" && pwd)
WORK=${MKDIST_WORK:-$TOP/build/dist}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH
PY="python3 -I -B"
P=${VERANDA_PROJECTS:-$HOME/Projects}   # (the sibling repositories' folder)
GEOWRITE=${GEOWRITE:-}                  # (dropped: only when asked for)
CALC=${CALC:-$P/commander-calc}
GEOCHESS=${GEOCHESS:-$P/veranda-geochess}
TOPDESK=${TOPDESK:-}                    # (dropped: only when asked for)
X16MOD=${X16MOD:-$P/x16-mod}
SOLITAIRE=${SOLITAIRE:-$P/veranda-solitaire}
CWRITE=${CWRITE:-$P/commander-write}
PINBALL=${PINBALL:-$P/veranda-pinball}
HWALLS=${HWALLS:-$P/harbour-walls}
SIDPLAY=${SIDPLAY:-$P/veranda-sidplay}
VERSION=${VERANDA_VERSION:-$(cat VERSION 2>/dev/null || echo 0.0.0)}
# the build id and date (UPDATE.LST, the README, About this X16): this
# tree's short hash and today; the release workflow passes the source's
# (VERANDA_BUILD: the commit of this tree the public one was exported
# from, so a card's build is the same either way; DECISIONS V139)
BUILDID=${VERANDA_BUILD:-$(git rev-parse --short HEAD)}
BDATE=${VERANDA_DATE:-$(date +%Y-%m-%d)}

say() { echo "mkdist: $*"; }
die() { echo "mkdist: $*" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/b" "$WORK/src"
V=$DEST/VERANDA
[ ! -e "$V" ] || die "$V is there already (a new, empty <dest>)"
mkdir -p "$V/APPS" "$V/FONTS" "$V/WALLPAPERS" "$DEST/DOCUMENTS"

# ---------------------------------------------------------------- Veranda
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || die "the API table"
$PY tools/kbuild.py >/dev/null || die "the kernel does not build"
tools/mksdk.sh "$WORK/sdk" >/dev/null || die "the SDK does not install"
SDK=$WORK/sdk
cp build/VERANDA.PRG build/VERANDA.SYS build/RBOOT "$V/"
cp build/VERANDA.PRG "$V/AUTOBOOT.X16"
cp -r shell "$WORK/b/shell"
rm -f "$WORK/b/shell"/*.cvt "$WORK/b/shell"/*.bin "$WORK/b/shell"/*.map
make -s -C "$WORK/b/shell" SDK="$SDK" >"$WORK/b/shell.log" 2>&1 || { tail "$WORK/b/shell.log"; die "the shell"; }
cp "$WORK/b/shell/SHELL.cvt" "$V/"
app() {                 # $1 apps/<dir>, $2 the folder in the package, then "built=on the card" ...
	local d=$1 to=$2 b=$WORK/b/$(basename "$1")
	shift 2
	mkdir -p "$b"
	make -s -C "$d" all SDK="$SDK" OUT="$b" BUILD="$BUILDID" >"$b/build.log" 2>&1 || { tail "$b/build.log"; die "$d"; }
	for f in "$@"; do
		cp "$b/${f%%=*}" "$to/${f#*=}"
	done
}
app apps/setup "$V" "Setup.cvt=Veranda Setup.cvt"
# (the names the cards had before V71, so Veranda Setup finds the old
# copies of the same programs: DECISIONS V71)
app apps/paint "$V/APPS" "Paint.cvt=Paint.cvt"
app apps/cpaint "$V/APPS" "ColourPaint.cvt=Colour Paint.cvt"
# (Colour Paint next to Paint until the user retires it: V173)
app apps/edit "$V/APPS" "Edit.cvt=Veranda Edit.cvt"
app apps/view "$V/APPS" "View.cvt=View.cvt"
app apps/archive "$V/APPS" "Archive.cvt=Archive.cvt"
app apps/term "$V/APPS" "Term.cvt=Term.cvt"
app apps/ftp "$V/APPS" "FTP.cvt=Veranda FTP.cvt"
app apps/gopher "$V/APPS" "Gopher.cvt=Veranda Gopher.cvt"
app apps/gemini "$V/APPS" "Gemini.cvt=Veranda Gemini.cvt" "Wikipedia.cvt=Wikipedia.cvt"
# (Wikipedia.cvt: the Wikipedia launcher, a document of Veranda Gemini's: V128)
# (its private web proxy runs on a PC: PC/; V124)
mkdir -p "$DEST/PC"
cp tools/web_proxy.py "$DEST/PC/web_proxy.py"
app apps/irc "$V/APPS" "Chat.cvt=Veranda Chat.cvt"
app apps/claude "$V/APPS" "Claude.cvt=Veranda Claude.cvt"
# (its bridge to Claude Code runs on a PC: the card's top level, PC/; V115)
mkdir -p "$DEST/PC"
cp tools/claude_bridge.py "$DEST/PC/claude_bridge.py"
app apps/ask "$V/APPS" "Ask.cvt=Veranda Ask.cvt"
# (its sign-in helper runs on a PC too: PC/; V116)
cp tools/chatgpt_signin.py "$DEST/PC/chatgpt_signin.py"
app apps/disktools "$V/APPS" "DiskTools.cvt=Disk Tools.cvt"
app apps/about "$V/APPS" "About.cvt=About this X16.cvt"
app apps/update "$V/APPS" "Update.cvt=Veranda Update.cvt"
# (its PC source runs on a PC: PC/; V130)
cp tools/update_server.py "$DEST/PC/update_server.py"
app apps/fonted "$V/APPS" "FontEd.cvt=FontEd.cvt"
app apps/calc "$V/APPS" "Calculator.cvt=Calculator.cvt"
app apps/notepad "$V/APPS" "NotePad.cvt=Note Pad.cvt"
app apps/dex "$V/APPS" "Dex.cvt=Dex.cvt"
app apps/calendar "$V/APPS" "Calendar.cvt=Calendar.cvt"
app apps/prefs "$V/APPS" "Preferences.cvt=Preferences.cvt"
app apps/scrapman "$V/APPS" "PhotoMgr.cvt=PhotoMgr.cvt" "TextMgr.cvt=TextMgr.cvt"
# VeraBASIC (DECISIONS V93): the editor (it opens .bas files) and VeraBASIC
# Run (program documents)
b=$WORK/b/vbasic
mkdir -p "$b"
make -s -C apps/vbasic ide SDK="$SDK" OUT="$b" >"$b/build.log" 2>&1 || { tail "$b/build.log"; die "VeraBASIC"; }
cp "$b/ide/VeraBASIC.cvt" "$V/APPS/VeraBASIC.cvt"
make -s -C apps/vbasic all SDK="$SDK" OUT="$b" >>"$b/build.log" 2>&1 || { tail "$b/build.log"; die "VeraBASIC Run"; }
cp "$b/VBRun.cvt" "$V/APPS/VeraBASIC Run.cvt"
# its help (VR_HELPDIR) and the example programs
mkdir -p "$V/HELP" "$DEST/DOCUMENTS/VeraBASIC Examples"
$PY tools/vbgen.py >/dev/null || die "vbgen.py (the help files)"
cp vbasic/gen/HELP/KEYWORDS.HLP vbasic/gen/HELP/ERRORS.HLP vbasic/gen/HELP/TUTORIAL.HLP vbasic/gen/HELP/EDITOR.HLP \
	vbasic/gen/HELP/MANUAL.HLP "$V/HELP/"
# the manual's reference card as a PDF (DECISIONS V99: tools/vbmanual.py)
$PY tools/vbasic.py doc "$WORK/manual" >/dev/null || die "the manual (vbasic.py doc)"
cp "$WORK/manual/VeraBASIC-reference-card.pdf" "$V/HELP/Reference card.pdf"
# Veranda's own manual (docs/manual) as plain text, for View: the shell's
# Veranda > Help opens "Veranda manual.txt" (DECISIONS V134: tools/mkhelp.py)
$PY tools/mkhelp.py "$V/HELP" || die "the manual (mkhelp.py)"
X="$DEST/DOCUMENTS/VeraBASIC Examples"
cp docs/vbasic/examples/notes.bas "$X/Notes.bas"
cp docs/vbasic/examples/dice.bas "$X/Dice.bas"
cp docs/vbasic/examples/addressbook.bas "$X/Address book.bas"
cp docs/vbasic/examples/tiles.bas "$X/Tiles.bas"
for i in 1 2 3 4 5 6 7; do
	cp "tests/vbasic/ui/bird$i.bas" "$X/Bird Watch - tutorial step $i.bas"
done
# a made application (DECISIONS V99): Bird Watch, the tutorial's step 7 with
# its APP lines and its own tile, made by vbasic.py app as File > Make
# application... makes it; Garden.brd, its document, in /DOCUMENTS
cp docs/vbasic/examples/birdwatch.bas "$X/Bird Watch.bas"
$PY tools/vbasic.py app docs/vbasic/examples/birdwatch.bas --run "$V/APPS/VeraBASIC Run.cvt" \
	-o "$V/APPS/Bird Watch.cvt" || die "Bird Watch, the application (vbasic.py app)"
printf '42\n' > "$DEST/DOCUMENTS/Garden.brd"
$PY tools/fontcvt.py testfonts "$WORK/fonts" >/dev/null || die "the fonts"
cp "$WORK/fonts/Gate Sans.cvt" "$WORK/fonts/Gate Mono.cvt" "$V/FONTS/"
$PY tools/mkwall.py -o "$V/WALLPAPERS/Dusk.cvt" --dusk 2>/dev/null || die "the wallpaper"
$PY tools/wall_stillwater.py "$V/WALLPAPERS/Still Water.cvt" >/dev/null || die "Still Water (tools/wall_stillwater.py needs Pillow)"
$PY tools/wall_hills.py "$V/WALLPAPERS/Low Hills.cvt" >/dev/null || die "Low Hills"
$PY tools/wall_tiles.py "$V/WALLPAPERS/Sunroom Tiles.cvt" >/dev/null || die "Sunroom Tiles"
say "Veranda: the system, the shell, Setup, $(ls "$V/APPS" | wc -l) programs, 2 fonts, 4 wallpapers"

# ---------------------------------------------------------------- the ports
# export <tree> <ref...>: the first ref that exists, into $WORK/src/<name>
export_tree() {
	local tree=$1 name ref r
	name=$(basename "$tree")
	shift
	for r in "$@"; do
		if git -C "$tree" rev-parse --verify -q "$r^{commit}" >/dev/null; then
			ref=$r
			break
		fi
	done
	[ -n "$ref" ] || return 1
	mkdir -p "$WORK/src/$name"
	git -C "$tree" archive "$ref" | tar -x -C "$WORK/src/$name"
	echo "$name at $ref ($(git -C "$tree" rev-parse --short "$ref"))" >> "$WORK/refs.txt"
	echo "$WORK/src/$name"
}
port() {                # $1 the name, $2 the tree, $3 the refs (space separated), $4 the build, $5 its output, $6 the name on the card
	local s
	if [ ! -d "$2/.git" ] && [ ! -f "$2/.git" ]; then
		say "WARNING: no $1 ($2): left out"
		return
	fi
	# shellcheck disable=SC2086
	s=$(export_tree "$2" $3) || { say "WARNING: $1: none of the refs $3: left out"; return; }
	(cd "$s" && eval "$4") >"$WORK/b/$1.log" 2>&1 || { tail "$WORK/b/$1.log"; die "$1 does not build"; }
	cp "$s/$5" "$V/APPS/$6"
	say "$1: $(tail -1 "$WORK/refs.txt")"
}
# Inside veranda-x16 (MONO): its ../apps instead of the sibling repositories
MONO=0
if [ -f "$TOP/../apps/calc/Makefile" ] && [ -f "$TOP/../apps/modplayer/Makefile" ] && [ "${MKDIST_SIBLINGS:-0}" = 0 ]; then
	MONO=1
	APPS=$(cd "$TOP/../apps" && pwd)
fi
# local_app <name> <apps dir> <the build> <its output> <the name on the card>:
# an application of veranda-x16's ../apps, copied into $WORK/src
local_app() {
	local s=$WORK/src/$(basename "$2") rev
	[ -d "$2" ] || { say "WARNING: no $1 ($2): left out"; return; }
	mkdir -p "$s"
	tar -C "$2" --exclude=./build -cf - . | tar -x -C "$s"
	(cd "$s" && eval "$3") >"$WORK/b/$1.log" 2>&1 || { tail "$WORK/b/$1.log"; die "$1 does not build"; }
	cp "$s/$4" "$V/APPS/$5"
	rev=$(git -C "$2" log -1 --format=%h -- . 2>/dev/null || true)
	echo "$1 from apps/$(basename "$2")${rev:+ ($rev)}" >> "$WORK/refs.txt"
	say "$1: apps/$(basename "$2")"
}
# sibling <name> <tree> <refs> <its ../apps dir in veranda-x16, - none> <the build> <its output> <the name on the card>
sibling() {
	if [ $MONO = 1 ]; then
		[ "$4" = - ] || local_app "$1" "$APPS/$4" "$5" "$6" "$7"
	else
		port "$1" "$2" "$3" "$5" "$6" "$7"
	fi
}
if [ -n "$GEOWRITE" ]; then sibling geoWrite "$GEOWRITE" "${GEOWRITE_REF:-main}" - "make SDK='$SDK' STAGE=8d" build/geoWrite.cvt geoWrite.cvt; fi
sibling "Veranda Calc" "$CALC" "${CALC_REF:-layout veranda}" calc "make veranda SDK='$SDK'" "build/veranda/Veranda Calc.cvt" "Veranda Calc.cvt"
sibling "Veranda Write" "$CWRITE" "${CWRITE_REF:-main}" commander-write "make veranda SDK='$SDK'" "build/veranda/Veranda Write.cvt" "Veranda Write.cvt"
sibling geoChess "$GEOCHESS" "${GEOCHESS_REF:-veranda}" - "make -C veranda SDK='$SDK'" build/veranda/geoChess.cvt geoChess.cvt
if [ -n "$TOPDESK" ]; then sibling TopDesk "$TOPDESK" "${TOPDESK_REF:-veranda}" - "make SDK='$SDK' STAGE=td3 MODE=640x240" build/TopDesk.cvt TopDesk.cvt; fi
sibling "MOD Player" "$X16MOD" "${X16MOD_REF:-layout veranda}" modplayer "make veranda VSDK='$SDK'" "build/veranda/MOD Player.cvt" "MOD Player.cvt"
sibling Solitaire "$SOLITAIRE" "${SOLITAIRE_REF:-main}" solitaire "make -C veranda SDK='$SDK'" "build/veranda/Veranda Solitaire.cvt" Solitaire.cvt
# (copied onto the card by hand until 1.0)
sibling "Lighthouse Pinball" "$PINBALL" "${PINBALL_REF:-master}" pinball "make -C veranda SDK='$SDK'" "build/veranda/Lighthouse Pinball.cvt" "Lighthouse Pinball.cvt"
sibling "Harbour Walls" "$HWALLS" "${HWALLS_REF:-master}" harbour-walls "make SDK='$SDK'" "build/app/Harbour Walls.cvt" "Harbour Walls.cvt"
sibling "SID Player" "$SIDPLAY" "${SIDPLAY_REF:-main}" sidplay "make build/app/app.cvt VSDK='$SDK'" build/app/app.cvt "SID Player.cvt"

# ---------------------------------------------------------------- README
{
	echo "VERANDA $VERSION - built $BDATE (Veranda $BUILDID)"
	cat <<'EOF'

THE FOLDERS (DECISIONS V71)
  /VERANDA            the system: VERANDA.PRG, VERANDA.SYS, AUTOBOOT.X16,
                      RBOOT, SHELL.cvt (the desktop), Veranda Setup
  /VERANDA/APPS       the applications and desk accessories
  /VERANDA/FONTS      fonts every program can load (Gate Sans; Gate Mono 10
                      and 12, monospaced)
  /VERANDA/WALLPAPERS desktop pictures: Dusk, Still Water, Low Hills,
                      Sunroom Tiles;
                      Preferences > Desktop chooses one, or a plain colour,
                      or a pattern. Your own: tools/mkwall.py picture.jpg
                      (in the SDK; a C compiler makes its helper once)
  /VERANDA/HELP       Veranda's manual as text (Veranda > Help in the
                      desktop opens it in View; Esc there lists its parts),
                      VeraBASIC's help files (F1 in the editor), the
                      VeraBASIC manual in help form, Reference card.pdf
  /VERANDA/.SYSTEM    hidden: the settings, alarms, the clipboard, the Note
                      File, the albums, the shell's desk file, the trash
  /DOCUMENTS          your files: where the shell opens and programs save

START
  DOS"CD:VERANDA"
  BOOT            (or LOAD"VERANDA.PRG" and RUN)
The shell opens in /DOCUMENTS; disk > documents opens it again, the card
icon the card's top folder. Double-click a document to open it with its
application from /VERANDA/APPS (.X16S .XLSX .ODS .CSV Veranda Calc, .TXT
Veranda Edit, .MOD MOD Player, .SID SID Player, .D64 .D71 .D81 Archive,
.TEL Term, .BMP View, .BAS VeraBASIC). BASIC (keep Veranda): back with
SYS 35328, or LOAD"RBOOT" and RUN (in /VERANDA).

VERANDA FTP
  An FTP client through TexElec's Serial & ESP32 Network Card (its Wi-Fi
  modem): the card and a server side by side. Connection > Sites... saves
  servers in /VERANDA/.SYSTEM/FTP.SITES; the passwords there are stored
  as plain text.

VERANDA GOPHER
  A Gopher reader through the same card: menus, texts, searches and
  downloads to /DOCUMENTS; type an address (gopher://host/1selector) or
  start from the bookmarks (/VERANDA/.SYSTEM/GOPHER.MARKS).

VERANDA GEMINI
  A Gemini browser through the same card: capsules' pages (gemtext: links,
  headings, lists, quotes, preformatted text), questions, redirects, plain
  texts, and other files saved to /DOCUMENTS. Type an address
  (gemini://host/path, or just the host) or start from the bookmarks
  (/VERANDA/.SYSTEM/GEMINI.MARKS, gemtext: one "=> URL name" a line).
  Tab moves from link to link, Return follows one; Ctrl+F finds a word.
  Gemini needs TLS: the modem makes it (Zimodem's ATCS, which your
  firmware must have) and does NOT check the capsule's certificate (no
  "trust on first use" either). Client certificates are not supported.
  Gopher and mail links only say where they lead.

  Web pages (http and https links, or such an address typed) can be read
  as gemtext. Following one asks: Yes opens it through NewsWaffle, No
  through your own proxy, Cancel neither. File > Settings... changes it:
  0 ask each time, 1 always NewsWaffle, 2 always my proxy, 3 never; then
  your proxy's host:port (port 1965 if none). Kept in
  /VERANDA/.SYSTEM/GEMINI.CFG.
  - NewsWaffle (gemini://gemi.dev/cgi-bin/waffle.cgi, a bookmark when you
    have no GEMINI.MARKS yet) is a free third-party service: it fetches
    the page and sends it back as gemtext, best for articles and news.
    It SEES EVERY PAGE YOU READ THROUGH IT. With a GEMINI.MARKS of your
    own (never replaced by this package), add the lines
        => gemini://gemi.dev/ gemi.dev
        => gemini://gemi.dev/cgi-bin/waffle.cgi NewsWaffle
  - Your own proxy: copy PC/web_proxy.py to a PC on your network (Python
    3, nothing to install) and run
        python3 web_proxy.py
    It makes a self-signed certificate with openssl the first time (or
    says how), listens on port 1965, takes requests from private (LAN)
    addresses only and logs one line a request; then File >
    Settings..., 2, and the PC's address. It keeps a page's article text,
    headings, lists and links (numbered after each paragraph); its own
    pages: gemini://<PC>/ (start), /search (DuckDuckGo), /go (an address).
    Other Gemini proxies take the same requests: Duckling proxy or levior
    (with TLS: the modem always speaks TLS).

  Pictures: a link to a picture has [Show image] after it; click it (or
  Tab to it and press Return: Yes show, No save) and a PNG is shown in
  the window in 16 colours (scaled to fit, dithered; Esc back to the page;
  Save or S copies it to /DOCUMENTS). Interlaced PNGs, JPEG, GIF and the
  others are not shown: save them. With Pillow on the PC
  (pip install pillow), web_proxy.py turns JPEG, GIF, WebP and BMP into
  PNGs Veranda Gemini shows. File > Settings... sets the largest picture
  shown without asking (256 KB). Common emoji and symbols show as short
  ASCII (>> << * !); others as ?.

  Wikipedia: double-click Wikipedia in /VERANDA/APPS (the W on a globe):
  Veranda Gemini starts and asks "Look up in Wikipedia:". In Veranda
  Gemini, Go > Wikipedia... (Ctrl+W) asks the same, and typing
  "wp Ada Lovelace" (or "w Ada Lovelace") in the address line looks it
  up; "wp" alone asks. The article comes through Gemipedia
  (gemini://gemi.dev/cgi-bin/wp.cgi/), a free public Gemini front end to
  Wikipedia by NewsWaffle's author: an exact title is not needed (no
  article: its search). File > Settings... sets Wikipedia's language, a
  code such as en (the default), pl, de or fr. Gemipedia's front page and
  its featured articles are bookmarks when you have no GEMINI.MARKS yet;
  with your own, add
      => gemini://gemi.dev/cgi-bin/wp.cgi/ Gemipedia: Wikipedia
      => gemini://gemi.dev/cgi-bin/wp.cgi/featured Wikipedia: featured articles
  (Polish: .../wp.cgi/welcome/pl and .../wp.cgi/featured/pl).

VERANDA CHAT
  An IRC client through the same card: channels and private messages as
  tabs, the nick list, plain port 6667 (no TLS). Servers, nicks and the
  channels to join are in /VERANDA/.SYSTEM/CHAT.SERVERS (a password
  there is plain text).

VERANDA CLAUDE
  A conversation with Claude (Anthropic's API, your own API key from
  console.anthropic.com) through the same card. The modem makes the TLS
  connection (Zimodem's ATCS, which your firmware must have: ATI in Term
  shows its version) and does NOT check the certificate. The key is kept
  as plain text in /VERANDA/.SYSTEM/CLAUDE.CFG (key=sk-ant-...).
  Or use your claude.ai plan through your own Claude Code on a PC: copy
  PC/claude_bridge.py from this card to a PC where Claude Code (claude)
  is installed and signed in, and run there (Python 3)
      python3 claude_bridge.py --password something-long
  Then in Veranda Claude's Settings choose "Claude Code on my PC" and type
  the PC's IP address (port 8642, e.g. 192.168.1.20:8642) and the same
  password. Claude Code runs with every tool off: the X16 can only talk.
  The connection is plain TCP: the password and the conversation cross
  your home network unencrypted.
  Code in a reply (a fenced block) is shaded, with [Copy], [Save...] and
  for BASIC [Save .PRG]: a program the X16's BASIC can LOAD and RUN.
  Code > Attach a file... (or Attach) sends a file from /DOCUMENTS with
  your next question (text, a .cwr, a BASIC .PRG made text); the reply's
  new version saves back over it. Each question sends the whole
  conversation again: Settings > Conversation... (Remember the last 10
  or 4 messages, short answers, old code shortened, compact when long)
  and Settings > Compact conversation keep it small; the status bar
  shows each turn's tokens and, with an API key, an estimate in dollars.
  Every conversation is saved after each turn in /DOCUMENTS/Chats/Claude
  (one .chat file a chat): File > Chats... (Ctrl+L) opens, renames and
  deletes them; File > New no longer asks.

VERANDA ASK
  A conversation with OpenAI's models through the same card, with your
  ChatGPT plan (Sign in with ChatGPT: ChatGPT Plus or Pro) or an OpenAI
  API key. The X16 has no browser, so you sign in from a PC on your
  network: copy PC/chatgpt_signin.py from this card to a PC with a web
  browser and Python 3, and run there
      python3 chatgpt_signin.py
  It prints a 6-digit code and the PC's address. In Veranda Ask choose
  Settings, ChatGPT plan, type the PC's address (port 8643, e.g.
  192.168.1.20:8643) and the code, then Continue with ChatGPT: the PC's
  browser opens OpenAI's sign-in page. When you have signed in, the X16
  gets its credentials over your network and the helper exits; the PC
  keeps no copy. (Or, with this card in the PC:
      python3 chatgpt_signin.py --card /path/to/the/card/VERANDA
  writes them onto the card.) From then on the X16 renews its sign-in
  by itself; when the sign-in has ended (after 30 days unused, or when
  you sign out elsewhere) it says "sign in again from your PC".
  Eligible usage counts against your ChatGPT plan's limits; when a limit
  is reached Veranda Ask says so (no reset time is given): review your
  plan or this app's limit at chatgpt.com/settings/usage. A plan other
  than Plus or Pro cannot be used.
  The tokens are kept as plain text in /VERANDA/.SYSTEM/ASK.CFG (the
  card's FAT has no permissions): anyone with the card can use your plan
  through it. Keep the card to yourself; sign in again to replace them.
  The code and the credentials cross your home network unencrypted
  during the sign-in (plain HTTP; only private addresses may connect).
  Or use an OpenAI API key (platform.openai.com, paid by the token):
  Settings, OpenAI API key, or a line key=sk-... in ASK.CFG.
  The modem makes the TLS connections to OpenAI (Zimodem's ATCS) and
  does NOT check the certificates.
  Code blocks, attached files, Remember and Compact work as in Veranda
  Claude (above); with the ChatGPT plan the status bar shows tokens, no
  money. Its chats are kept in /DOCUMENTS/Chats/Ask.

THE NETWORK CHECKLIST (Veranda FTP, Gopher, Gemini, Chat, Claude, Ask, Update)
  - TexElec's Serial & ESP32 Network Card, its Wi-Fi set up (Term: ATI)
  - Veranda Gemini, Claude and Ask: Zimodem with ATCS (TLS by the modem;
    Gemini's port 1965 open on your network)
  - Veranda Ask with your ChatGPT plan: a PC on the same network with a
    browser and Python 3 for PC/chatgpt_signin.py (port 8643 open to the
    X16; port 1455 free on the PC for the browser's way back)
  - Veranda Claude with Claude Code: PC/claude_bridge.py on such a PC
    (port 8642)
  - Veranda Gemini with your own web proxy: PC/web_proxy.py on such a PC
    (port 1965 open to the X16; openssl for its certificate); a web link,
    No (my proxy): the page as gemtext, its links through the proxy too
  - Veranda Update from GitHub: Zimodem with ATCS (github.com and its
    download host on port 443); from your PC: PC/update_server.py on
    such a PC (port 8644)

DISK TOOLS
  The SD card looked after: its name (Rename...), size, free space and
  cluster size; Space use (the folders by size, a bar each, click to go
  in); Check, which reads the FAT and every folder and reports what it
  finds: it NEVER writes to the card and repairs nothing; Clean up: empty
  the trash, and delete the files Veranda's own programs leave when a save
  is cut short (~VEDIT.TMP, ~VBASIC.TMP, the Font Editor's NAME.tmp,
  Veranda Ask's ASK.TMP), each kind only after its own OK. No formatting:
  Veranda runs from this card.

VERANDA UPDATE
  Brings this card up to date online: Check fetches the list of files of
  the newest build (UPDATE.LST) and compares the card's files with it
  (their sizes and CRC-32s), showing what changed and what is new, its
  size and "what's new"; Update fetches them, checks each one's CRC-32,
  and only when all have come puts them in place, Veranda's system files
  last, then "Restart to finish". The replaced files are kept in
  /VERANDA/.SYSTEM/OLD/<build>/: Undo last update puts them back. A
  dropped connection, Esc or a file that fails its check leaves the card
  as it was; Update again goes on where it stopped. Your documents, your
  settings and any file the list does not name are never touched (files
  no longer in the list are not deleted either). Source... chooses:
  - GitHub releases (owner/repo, veranda-x16/veranda at first): only
    Veranda, the author's own programs and those released with credit
    (geoChess, Solitaire, SID Player, MOD Player) are published there;
    the ports for personal use never are. The modem makes the
    TLS connection (Zimodem's ATCS) and does NOT check the certificate.
  - A PC on your network: copy PC/update_server.py to a PC with your own
    Veranda package (a folder like this one) and run there (Python 3)
        python3 update_server.py /path/to/the/package
    then type the PC's address and port (8644, e.g. 192.168.1.20:8644).
    Plain HTTP on your network; only private addresses may connect; it
    serves your whole package, ports and all, so never open its port to
    the Internet.
  The setting is kept in /VERANDA/.SYSTEM/UPDATE.CFG. About this X16 shows
  the build this card has (VERANDA/UPDATE.LST).

ABOUT THIS X16
  Veranda's and the ROM's versions, the CPU's speed, VERA's and the SMC's
  versions, the memory (the programs put aside with Alt+Tab, their banks),
  the card, the network card, the clock. Ask the modem sends AT and ATI
  only (its firmware's line: check ATCS there). Copy puts it all on the
  clipboard as text, for a bug report.

THE HARDWARE CHECKLIST (Disk Tools, About this X16)
  - About this X16: KERNAL ROM R49 (or your release); Machine "Commander
    X16"; CPU about 8.0 MHz; VERA 0.3.x and the SMC's version shown (or
    "the SMC does not say"); RAM 512 KB: 64 banks, 44 for programs with
    nothing aside; put a program aside with Alt+Tab, open About again: it
    is listed with its banks; the card's name and size; the network
    card at $9FE0 and Ask the modem: the Zimodem line (ATCS for Claude and
    Ask); the clock; Copy, then paste in Veranda Edit
  - Disk Tools: Card: the size, the free space and the cluster size as a
    PC shows them (Rename... and back); Space use: Esc stops a count,
    Alt+Tab during one stops it and says so when back; Check on your card
    (it only reads: a PC's fsck or chkdsk on the same card should agree;
    a card a PC repaired should show no problems); Clean up: a file put
    in the shell's trash, then Empty the trash...

VERABASIC
  VeraBASIC is a BASIC with Veranda's windows, menus, dialogs and files:
  the editor (VeraBASIC: write, Check with Ctrl+K, Run with Ctrl+R, F1 for
  help) and VeraBASIC Run for finished programs. Example programs and the
  tutorial's seven steps are in /DOCUMENTS/VeraBASIC Examples. File > Make
  application... turns a program into an application of its own: Bird
  Watch in /VERANDA/APPS is one (it opens Garden.brd in /DOCUMENTS).

A CARD FROM BEFORE (everything in /VERANDA)
  Copy this package's VERANDA folder over the card's (replace the files)
  and its DOCUMENTS folder to the card's top. At the next start the shell
  runs Veranda Setup once: the settings, the Note File, the scraps and the
  trash go to /VERANDA/.SYSTEM, the applications to /VERANDA/APPS (an old
  copy of one that APPS has now goes to /VERANDA/.SYSTEM/OLD), the fonts
  to FONTS, your documents (.cvt documents, .TXT, .BMP, .MOD ...) to
  /DOCUMENTS (a name taken there gets ~2). Programs (.PRG) and your own
  folders stay where they are. Nothing is deleted; what moved where is in
  /VERANDA/.SYSTEM/LAYOUT.LOG.
EOF
	pp=$(cd "$V/APPS" && for f in geoWrite TopDesk; do [ ! -f "$f.cvt" ] || printf '%s ' "$f"; done)
	if [ -n "$pp" ]; then
		echo
		case $pp in
		*' '?*) echo "$(echo $pp | sed 's/ / and /') are ports for personal use: do not share this folder." ;;
		*) echo "$(echo $pp) is a port for personal use: do not share this folder." ;;
		esac
	fi
	echo
	echo "BUILT FROM"
	echo "  Veranda $BUILDID"
	sed 's/^/  /' "$WORK/refs.txt" 2>/dev/null || true
} > "$V/README.txt"

# ---------------------------------------------------------------- UPDATE.LST
# Veranda Update's list of every file above (V130: tools/mkmanifest.py):
# the build (the short hash, today), what's new (NOTES: a file of text,
# else the last commit's subject, its first sentence), one line a file
if [ -n "$NOTES" ]; then
	set -- --notes-file "$NOTES"
else
	set -- --note "$(git log -1 --format=%s | sed 's/\. .*/./' | cut -c1-300)"
fi
$PY tools/mkmanifest.py "$DEST" --build "$BUILDID" --date "$BDATE" --version "$VERSION" "$@" \
	>/dev/null || die "the manifest (mkmanifest.py)"
say "UPDATE.LST: $(grep -c '^file ' "$V/UPDATE.LST") files"

# nothing of a test may go in
bad=$(find "$DEST" \( -iname '*.TST' -o -iname '*.STP' -o -iname '*.PLY' -o -iname 'dump.bin' -o -iname 'console.txt' \
	-o -iname '*.map' -o -iname '*.bin' -o -iname 'TEST.PRG' -o -iname 'AUTOSTART.cvt' \) -print)
[ -z "$bad" ] || die "test files in the package: $bad"
say "the package in $DEST: $(find "$DEST" -type f | wc -l) files"
find "$DEST" -type f | sed "s|^$DEST/|  |" | sort
