#!/bin/bash
# tools/tocard.sh against a made-up card (a folder: never a real card).
#
#   tests/test_tocard.sh <work-dir>
#
# Two made-up packages: A (with TopDesk.cvt) and B (TopDesk.cvt dropped,
# Paint.cvt changed, a new program). A card with the user's files
# (DOCUMENTS/Mine.cvt, picture.cvt, a changed Garden.brd, .SYSTEM's
# settings, a folder of the user's own) gets A, then B:
#   1. A onto a card without Veranda: every file copied, the user's untouched
#   2. B: TopDesk.cvt moved to /VERANDA/.SYSTEM/OLD, Paint.cvt replaced,
#      Garden.brd (the user's version) kept, the backup made, the log
#   3. refused (exit 3, the card as it was, no backup): an application
#      changed on the card since it was installed (its CRC not the card's
#      UPDATE.LST's); a file the list does not name written on the card
#      after the install; a package that has a file of a user's name
#   4. --force: the changed application overwritten (it is in the backup)
#   5. --dry-run writes nothing
# MIT licence (see LICENSE).
set -e
cd "$(dirname "$0")/.."
W=${1:?usage: tests/test_tocard.sh <work-dir>}
rm -rf "$W"
mkdir -p "$W"
W=$(cd "$W" && pwd)
PY="python3 -I -B"
ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
sums() { (cd "$1" && find . -type f ! -path './VERANDA/.SYSTEM/OLD/*' -print0 | sort -z | xargs -0 sha256sum); }

mkpkg() {               # $1 the folder, $2 A or B
	local P=$1
	mkdir -p "$P/VERANDA/APPS" "$P/VERANDA/FONTS" "$P/PC" "$P/DOCUMENTS/VeraBASIC Examples" "$P/TILEHW"
	printf 'prg %s' "$2" > "$P/VERANDA/VERANDA.PRG"
	cp "$P/VERANDA/VERANDA.PRG" "$P/VERANDA/AUTOBOOT.X16"
	printf 'sys %s' "$2" > "$P/VERANDA/VERANDA.SYS"
	printf 'readme %s' "$2" > "$P/VERANDA/README.txt"
	printf 'paint %s' "$2" > "$P/VERANDA/APPS/Paint.cvt"
	printf 'edit' > "$P/VERANDA/APPS/Veranda Edit.cvt"
	printf 'font' > "$P/VERANDA/FONTS/Gate Sans.cvt"
	printf 'server %s' "$2" > "$P/PC/update_server.py"
	printf '42\n' > "$P/DOCUMENTS/Garden.brd"
	printf '10 PRINT\n' > "$P/DOCUMENTS/VeraBASIC Examples/Dice.bas"
	printf 'tile' > "$P/TILEHW/TILEHW.PRG"
	if [ "$2" = A ]; then
		printf 'topdesk' > "$P/VERANDA/APPS/TopDesk.cvt"
	else
		printf 'new' > "$P/VERANDA/APPS/Veranda Update.cvt"
	fi
	$PY tools/mkmanifest.py "$P" --build "${2}a${2}a${2}a1" --date 2026-11-21 --version 1.0 >/dev/null 2>&1
}
mkpkg "$W/pkgA" A
mkpkg "$W/pkgB" B
C=$W/card
mkdir -p "$C/DOCUMENTS" "$C/Photos"
# (the names the user keeps: TOCARD_KEEP, as tocard.keep would give them)
export TOCARD_KEEP=mine.cvt,picture.cvt,picture.pdf
printf 'mine' > "$C/DOCUMENTS/Mine.cvt"
printf 'picture' > "$C/DOCUMENTS/picture.cvt"
printf 'pdf' > "$C/DOCUMENTS/picture.pdf"
printf 'a photo' > "$C/Photos/cat.bmp"
export BACKUPS=$W/backups

# 1. A onto a card without Veranda
tools/tocard.sh "$W/pkgA" "$C" > "$W/1.log" 2>&1 || { cat "$W/1.log"; fail "1: A onto a new card"; }
grep -q 'verified: ' "$W/1.log" || fail "1: not verified"
for f in VERANDA/APPS/TopDesk.cvt VERANDA/UPDATE.LST TILEHW/TILEHW.PRG; do
	cmp -s "$W/pkgA/$f" "$C/$f" || fail "1: $f not copied"
done
[ "$(cat "$C/DOCUMENTS/Mine.cvt")" = mine ] && [ -f "$C/Photos/cat.bmp" ] || fail "1: the user's files"
ok "A onto a card without Veranda: $(grep -c . "$W/pkgA/VERANDA/UPDATE.LST") lines of UPDATE.LST, every file copied and compared, the user's files untouched"

# the user works on the card: settings, a changed example, a document
mkdir -p "$C/VERANDA/.SYSTEM"
printf 'key=sk-secret' > "$C/VERANDA/.SYSTEM/ASK.CFG"
printf 'prefs' > "$C/VERANDA/.SYSTEM/Veranda Prefs.cvt"
printf '43\n' > "$C/DOCUMENTS/Garden.brd"
printf 'mine too' > "$C/VERANDA/APPS/My Own App.cvt"
before=$(sums "$C" | grep -v ' ./VERANDA/\(APPS/Paint.cvt\|APPS/TopDesk.cvt\|APPS/Veranda Update.cvt\|VERANDA.PRG\|AUTOBOOT.X16\|VERANDA.SYS\|README.txt\|UPDATE.LST\)$\| ./PC/update_server.py$')

# 3. refusals first (the card must stay as it is)
all=$(sums "$C")
printf 'paint, changed on the X16' > "$C/VERANDA/APPS/Paint.cvt"
touch -d '2026-11-21 10:00' "$C/VERANDA/VERANDA.SYS"
all=$(sums "$C")
set +e
tools/tocard.sh "$W/pkgB" "$C" > "$W/3a.log" 2>&1
rc=$?
set -e
[ $rc = 3 ] || { cat "$W/3a.log"; fail "3: a changed application: exit $rc, not 3"; }
grep -q 'REFUSED.*Paint.cvt.*changed on the card since it was installed' "$W/3a.log" || { cat "$W/3a.log"; fail "3: why"; }
[ "$all" = "$(sums "$C")" ] && [ "$(ls "$BACKUPS" | wc -l)" = 1 ] || fail "3: the card changed or a backup was made"
# an unlisted file written on the card after the install
cp "$W/pkgA/VERANDA/APPS/Paint.cvt" "$C/VERANDA/APPS/Paint.cvt"
printf 'tile, mine' > "$C/TILEHW/TILEHW.PRG"
touch -d '2026-11-21 15:00' "$C/TILEHW/TILEHW.PRG"
all=$(sums "$C")
set +e
tools/tocard.sh "$W/pkgB" "$C" > "$W/3b.log" 2>&1
rc=$?
set -e
[ $rc = 3 ] && grep -q 'REFUSED.*TILEHW/TILEHW.PRG.*written on the card after the last install' "$W/3b.log" ||
	{ cat "$W/3b.log"; fail "3: an unlisted file written after the install"; }
[ "$all" = "$(sums "$C")" ] || fail "3b: the card changed"
cp "$W/pkgA/TILEHW/TILEHW.PRG" "$C/TILEHW/TILEHW.PRG"
touch -d '2026-11-21 10:00' "$C/TILEHW/TILEHW.PRG"
# a package with a file of a user's name, which the card has otherwise
cp -r "$W/pkgB" "$W/pkgU"
printf 'not yours' > "$W/pkgU/DOCUMENTS/../VERANDA/picture.cvt"
printf 'yours' > "$C/VERANDA/picture.cvt"
set +e
tools/tocard.sh --dry-run "$W/pkgU" "$C" > "$W/3c.log" 2>&1
rc=$?
set -e
[ $rc = 3 ] && grep -q 'REFUSED.*VERANDA/picture.cvt.*a name of the user' "$W/3c.log" || { cat "$W/3c.log"; fail "3: a user's name"; }
rm "$C/VERANDA/picture.cvt"
ok "refused, the card as it was and no backup: an application changed since it was installed (its CRC), an unlisted file written after the install (its date), a file of a user's name"

# 5. --dry-run
all=$(sums "$C")
tools/tocard.sh --dry-run "$W/pkgB" "$C" > "$W/5.log" 2>&1 || { cat "$W/5.log"; fail "5: dry run"; }
[ "$all" = "$(sums "$C")" ] && [ "$(ls "$BACKUPS" | wc -l)" = 1 ] && grep -q 'to move to VERANDA/.SYSTEM/OLD: VERANDA/APPS/TopDesk.cvt' "$W/5.log" ||
	{ cat "$W/5.log"; fail "5: the dry run wrote or did not plan"; }
ok "--dry-run: the plan (TopDesk.cvt to .SYSTEM/OLD), nothing written"

# 2. B
tools/tocard.sh "$W/pkgB" "$C" > "$W/2.log" 2>&1 || { cat "$W/2.log"; fail "2: B"; }
[ -f "$C/VERANDA/.SYSTEM/OLD/TopDesk.cvt" ] && [ ! -e "$C/VERANDA/APPS/TopDesk.cvt" ] || fail "2: TopDesk.cvt not moved to OLD"
cmp -s "$W/pkgA/VERANDA/APPS/TopDesk.cvt" "$C/VERANDA/.SYSTEM/OLD/TopDesk.cvt" || fail "2: TopDesk.cvt not whole"
for f in VERANDA/APPS/Paint.cvt "VERANDA/APPS/Veranda Update.cvt" VERANDA/UPDATE.LST VERANDA/VERANDA.SYS PC/update_server.py; do
	cmp -s "$W/pkgB/$f" "$C/$f" || fail "2: $f is not B's"
done
[ "$(cat "$C/DOCUMENTS/Garden.brd")" = 43 ] || fail "2: the user's Garden.brd was overwritten"
after=$(sums "$C" | grep -v ' ./VERANDA/\(APPS/Paint.cvt\|APPS/TopDesk.cvt\|APPS/Veranda Update.cvt\|VERANDA.PRG\|AUTOBOOT.X16\|VERANDA.SYS\|README.txt\|UPDATE.LST\)$\| ./PC/update_server.py$')
[ "$before" = "$after" ] || { diff <(echo "$before") <(echo "$after"); fail "2: the user's files changed"; }
B=$(ls -d "$BACKUPS"/card-backup-* | sed -n 2p)
[ -f "$B/tocard.log" ] && [ -f "$B/VERANDA/APPS/TopDesk.cvt" ] && [ -f "$B/VERANDA/.SYSTEM/ASK.CFG" ] ||
	fail "2: the backup or its log"
grep -q 'kept (DOCUMENTS' "$W/2.log" || fail "2: Garden.brd not reported as kept"
ok "B: TopDesk.cvt (dropped) moved to /VERANDA/.SYSTEM/OLD whole; Paint.cvt, the system, PC replaced; Garden.brd (the user's) kept; $(echo "$before" | wc -l) files of the user's the same (.SYSTEM, DOCUMENTS, Photos, an app of the user's); the backup $(basename "$B") with tocard.log"

# 4. --force
printf 'paint, changed on the X16' > "$C/VERANDA/APPS/Paint.cvt"
touch -d '2026-11-21 10:00' "$C/VERANDA/VERANDA.SYS"
tools/tocard.sh --force "$W/pkgB" "$C" > "$W/4.log" 2>&1 || { cat "$W/4.log"; fail "4: --force"; }
cmp -s "$W/pkgB/VERANDA/APPS/Paint.cvt" "$C/VERANDA/APPS/Paint.cvt" || fail "4: --force did not overwrite"
B2=$(ls -d "$BACKUPS"/card-backup-* | sed -n 3p)
[ "$B2" != "$B" ] && [ "$(cat "$B2/VERANDA/APPS/Paint.cvt")" = 'paint, changed on the X16' ] || fail "4: the changed file is not in the second backup"
ok "--force: the changed Paint.cvt overwritten, kept in the backup $(basename "$B2")"
echo "TEST tocard: PASS"
