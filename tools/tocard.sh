#!/bin/bash
# A package onto the SD card (docs/RELEASING.md), the user's files kept.
#
#   tools/tocard.sh [--dry-run] [--force] <pkg> [<card>]
#
# <pkg>: a package (tools/release.sh's pkg-<version>-<hash>, or
# tools/mkdist.sh's); <card>: the card's top folder (its mount point);
# default: the one folder under /run/media/$USER that has a VERANDA folder.
#
#  1. tools/tocard.py plan: what the package writes. It REFUSES (nothing
#     written, exit 3) when it would overwrite a file that looks like the
#     user's: anything in VERANDA/.SYSTEM; a name the user keeps
#     (TOCARD_KEEP, else ~/Projects/veranda-dist/tocard.keep: tocard.py);
#     a file changed on the card since it was installed (its
#     size or CRC-32 not what the card's VERANDA/UPDATE.LST says); a file
#     that list does not name, written more than an hour after the card's
#     VERANDA.SYS. --force overwrites them (after the backup). A file the
#     card's DOCUMENTS has already is never written.
#  2. the backup: the card's VERANDA, DOCUMENTS, PC and TILEHW into
#     $BACKUPS/card-backup-<date> (then -<date>b, c ...), compared with the
#     card (diff -r).
#  3. the files an earlier package put on the card that this one no longer
#     has (in the card's UPDATE.LST, unchanged since; e.g. TopDesk.cvt)
#     are moved to /VERANDA/.SYSTEM/OLD/, not deleted.
#  4. rsync --checksum (a file of the same size and a near date is still
#     compared: VERANDA.PRG often keeps its size; no --delete: nothing of
#     the card's is deleted), then sync.
#  5. tools/tocard.py verify: every package file compared byte for byte
#     with the card's, the moved files whole, every other file of the four
#     folders unchanged (SHA-256 before and after).
# The log: $BACKUPS/card-backup-<date>/tocard.log (and on the screen).
# --dry-run: step 1 only.
#
#   BACKUPS=~/Projects/veranda-dist      where the backups go
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
DRY=0 FORCE=""
while [ $# -gt 0 ]; do
	case $1 in
	--dry-run) DRY=1 ;;
	--force) FORCE=--force ;;
	-*) echo "tocard: unknown option $1" >&2; exit 2 ;;
	*) break ;;
	esac
	shift
done
[ -n "$1" ] || { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
die() { echo "tocard: STOPPED: $*" >&2; exit 1; }
PKG=$(cd "$1" && pwd) || die "no package $1"
[ -f "$PKG/VERANDA/VERANDA.PRG" ] && [ -f "$PKG/VERANDA/UPDATE.LST" ] || die "$PKG is not a Veranda package (VERANDA/VERANDA.PRG, VERANDA/UPDATE.LST)"
CARD=$2
if [ -z "$CARD" ]; then
	set -- /run/media/"$USER"/*/VERANDA
	[ -d "$1" ] || die "no card with a VERANDA folder under /run/media/$USER: give the card's folder"
	[ $# = 1 ] || die "more than one card under /run/media/$USER ($*): give the card's folder"
	CARD=$(dirname "$1")
fi
CARD=$(cd "$CARD" && pwd) || die "no card folder $CARD"
case $CARD in
/ | "$HOME" | "$PKG" | "$PKG"/*) die "$CARD: not a card" ;;
esac
case $PKG in
"$CARD"/*) die "the package is on the card ($PKG)" ;;
esac
BACKUPS=${BACKUPS:-$HOME/Projects/veranda-dist}
B=$BACKUPS/card-backup-$(date +%Y-%m-%d)
for s in "" b c d e f g h i j k l m n o p q r s t u v w x y z; do
	[ -e "$B$s" ] || { B=$B$s; break; }
done
[ ! -e "$B" ] || die "no free backup name for $B"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tocard.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
LOG=$WORK/tocard.log
log() { echo "$*" | tee -a "$LOG"; }

log "tocard: $(date '+%Y-%m-%d %H:%M:%S'): $PKG -> $CARD"
log "tocard: the package: $(head -3 "$PKG/VERANDA/UPDATE.LST" | sed -n 's/^\(build\|version\) //p' | tr '\n' ' ')"
[ -f "$CARD/VERANDA/UPDATE.LST" ] &&
	log "tocard: the card has: $(head -3 "$CARD/VERANDA/UPDATE.LST" | sed -n 's/^\(build\|version\) //p' | tr '\n' ' ')"

# 1. the plan
set +e
python3 -I -B "$HERE/tocard.py" plan "$PKG" "$CARD" "$WORK" $FORCE 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
set -e
[ "$rc" = 0 ] || { [ "$rc" = 3 ] && echo "tocard: refused; the card is as it was" >&2; exit "$rc"; }
if [ "$DRY" = 1 ]; then
	log "tocard: a dry run: nothing written"
	exit 0
fi

# 2. the backup
mkdir -p "$B"
for d in VERANDA DOCUMENTS PC TILEHW; do
	[ -d "$CARD/$d" ] || continue
	rsync -rt "$CARD/$d" "$B/" || die "the backup of $d"
	diff -rq "$CARD/$d" "$B/$d" > /dev/null || die "the backup of $d is not the card's ($B/$d)"
done
log "tocard: the backup: $B ($(find "$B" -type f | wc -l) files, $(du -sh "$B" | cut -f1)), compared with the card"

# 3. the files no longer in the package
python3 -I -B "$HERE/tocard.py" move "$CARD" "$WORK" 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || die "moving to /VERANDA/.SYSTEM/OLD (the backup is in $B)"

# 4. the copy (no --delete; FAT keeps no owners or modes)
rsync -rt --checksum --modify-window=2 --no-perms --files-from="$WORK/copy.lst" "$PKG/" "$CARD/" 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || die "rsync (the backup is in $B)"
sync
log "tocard: copied $(wc -l < "$WORK/copy.lst") files; synced"

# 5. verify
python3 -I -B "$HERE/tocard.py" verify "$PKG" "$CARD" "$WORK" 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || die "the card is not as it should be (the backup is in $B)"
cp "$WORK"/*.lst "$WORK/user.sums" "$B/" 2>/dev/null || true
cp "$LOG" "$B/tocard.log"
echo "tocard: done; the log: $B/tocard.log"
