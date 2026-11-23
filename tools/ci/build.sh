#!/bin/bash
# A release built from the public source (the GitHub workflows release.yml
# and test.yml; DECISIONS V139). Also runs here, for a dry run.
#
#   tools/ci/build.sh <version> <out>             a stable release, tag v<version>
#   tools/ci/build.sh --test <out>                the Test channel's build
#
# SIBS: a folder with the organisation's sibling repositories checked out
# (commander-write, commander-calc, lighthouse-pinball, harbour-walls,
# veranda-sidplay, veranda-solitaire, mod-player), each at the tag v<version>
# (a test: its test branch, else main); a missing one is left out with
# mkdist's warning. geoWrite, geoChess and TopDesk are never looked for.
#
#   1. the fast gates (tools/ci/gates.sh; CI_GATES=, or NO_GATES=1)
#   2. the package: tools/mkdist.sh (VERANDA_BUILD: the source's build id,
#      from the commit's "Veranda-Source:" trailer, so the build is the one
#      the user's own package has)
#   3. UPDATE.LST with the version and the notes (the tag's message, else
#      the commit's)
#   4. the release: tools/mkrelease.py (tools/release.allow, the port
#      guard), --tag v<version>, or the channel test
#   5. the public SD-card zip (tools/mkpubzip.py), SHA256SUMS, NOTES.md
# <out> gets pkg/ (never published: it has README.txt and the programs the
# allowlist leaves out), rel/ (the release's assets) and the zip in rel/.
# It never publishes: the workflow uploads rel/.
set -e
cd "$(dirname "$0")/../.."
TOP=$PWD
PY="python3 -I -B"
TEST=0
[ "$1" = --test ] && { TEST=1; shift; }
if [ "$TEST" = 1 ]; then
	OUT=$1
	VER=$(cat VERSION)
else
	VER=$1 OUT=$2
fi
[ -n "$OUT" ] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
echo "$VER" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?(-[0-9A-Za-z]{1,6})?$' || { echo "build: version $VER: N.M or N.M.P" >&2; exit 2; }
[ "$TEST" = 1 ] || [ "$(cat VERSION)" = "$VER" ] || { echo "build: VERSION says $(cat VERSION), not $VER" >&2; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
say() { echo "build: $*"; }

# the build id: the source's (the trailer the export's commit carries)
SRCB=$(git log -1 --format=%B | sed -n 's/^Veranda-Source: Veranda \([0-9a-f]\{7,\}\)$/\1/p' | tail -1)
export VERANDA_BUILD=${VERANDA_BUILD:-${SRCB:0:7}}
export VERANDA_BUILD=${VERANDA_BUILD:-$(git rev-parse --short HEAD)}
export VERANDA_VERSION=$VER
say "Veranda $VER$([ "$TEST" = 1 ] && echo ' (test)'), build $VERANDA_BUILD, from $(git rev-parse --short HEAD)"

# 1. the gates
if [ "${NO_GATES:-0}" != 1 ]; then
	CI_LOGS=$OUT/gates tools/ci/gates.sh
fi

# 2. the package
S=${SIBS:-$TOP/../sibs}
sib() { [ -d "$S/$1/.git" ] && echo "$S/$1" || echo "/nonexistent/$1"; }
export CWRITE=$(sib commander-write) CWRITE_REF=HEAD
export CALC=$(sib commander-calc) CALC_REF=HEAD
export PINBALL=$(sib lighthouse-pinball) PINBALL_REF=HEAD
export HWALLS=$(sib harbour-walls) HWALLS_REF=HEAD
export SIDPLAY=$(sib veranda-sidplay) SIDPLAY_REF=HEAD
export SOLITAIRE=$(sib veranda-solitaire) SOLITAIRE_REF=HEAD
export X16MOD=$(sib mod-player) X16MOD_REF=HEAD
export GEOWRITE=/nonexistent/geowrite GEOCHESS=/nonexistent/geochess TOPDESK=
export MKDIST_SIBLINGS=1
# the notes: the tag's message (publish.sh: the release's points), else the commit's
if [ "$TEST" = 0 ] && git rev-parse -q --verify "refs/tags/v$VER" >/dev/null; then
	git tag -l --format='%(contents)' "v$VER" > "$OUT/message.txt"
else
	git log -1 --format=%B > "$OUT/message.txt"
fi
grep '^- ' "$OUT/message.txt" > "$OUT/whatsnew.txt" || echo "- Veranda $VER" > "$OUT/whatsnew.txt"
$PY tools/relnotes.py short --version "$VER" --notes "$OUT/whatsnew.txt" -o "$OUT/short.txt"
NOTES=$OUT/short.txt MKDIST_WORK=$OUT/mkdist tools/mkdist.sh "$OUT/pkg" > "$OUT/mkdist.log" 2>&1 ||
	{ tail -30 "$OUT/mkdist.log"; exit 1; }
grep '^mkdist: ' "$OUT/mkdist.log" | sed 's/^/  /'
for f in "Veranda Write" "Veranda Calc"; do
	[ -f "$OUT/pkg/VERANDA/APPS/$f.cvt" ] || { echo "build: $f.cvt is not in the package (its repository: SIBS=$S)" >&2; exit 1; }
done

# 3. UPDATE.LST again with the version and the notes
$PY tools/mkmanifest.py "$OUT/pkg" --build "$VERANDA_BUILD" --date "${VERANDA_DATE:-$(date +%Y-%m-%d)}" \
	--version "$VER" --notes-file "$OUT/short.txt" > "$OUT/manifest.out"

# 4. the release
if [ "$TEST" = 1 ]; then
	$PY tools/mkrelease.py "$OUT/pkg" "$OUT/rel" --channel test --repo "${REPO:-veranda-x16/veranda}" > "$OUT/mkrelease.log"
	ZIP=veranda-test-$VERANDA_BUILD-sdcard.zip
else
	$PY tools/mkrelease.py "$OUT/pkg" "$OUT/rel" --tag "v$VER" --repo "${REPO:-veranda-x16/veranda}" > "$OUT/mkrelease.log"
	ZIP=veranda-$VER-sdcard.zip
fi
grep -v '^gh \|^#\|to publish it' "$OUT/mkrelease.log" | sed 's/^/  /'

# 5. the zip, the sums, the notes
$PY tools/mkpubzip.py "$OUT/rel" "$OUT/rel/$ZIP"
{
	echo
	echo "## What is new"
	echo
	cat "$OUT/whatsnew.txt"
	echo
	echo "**To install by hand:** unzip \`$ZIP\` to the top of the SD card (INSTALL.txt). "
	echo "**To update:** Veranda Update, Check then Update. The other assets are its files, named by their CRC-32."
	echo
	echo "Built by GitHub Actions from the source at this tag (build $VERANDA_BUILD)."
} >> "$OUT/rel/NOTES.md"
(cd "$OUT/rel" && sha256sum "$ZIP" UPDATE.LST > SHA256SUMS)
echo "$ZIP" > "$OUT/zipname"
say "the release: $OUT/rel ($(ls "$OUT/rel" | wc -l) files, $(du -sh "$OUT/rel" | cut -f1)); the zip $ZIP"
