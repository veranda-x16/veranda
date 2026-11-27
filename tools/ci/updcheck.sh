#!/bin/bash
# The release and Veranda Update agree (DECISIONS V139): Veranda Update's
# test build, in the emulator, installs a release folder that was just
# built, from GitHub played on localhost with GitHub's addresses.
#
#   tools/ci/updcheck.sh <rel-dir> [stable|test]
#
# <rel-dir>: tools/mkrelease.py's folder (UPDATE.LST, the <crc32>.bin
# assets; the zip and SHA256SUMS beside them are ignored). The stand-in
# (tests/update_fake.py) serves it as veranda-x16/veranda: stable at
# /veranda-x16/veranda/releases/latest/download/UPDATE.LST, test at
# .../releases/download/test/UPDATE.LST, each file at
# .../releases/download/<the list's tag>/<asset>, every answer a 302 to
# another host with a signed address, as GitHub's. A card with no Veranda
# files gets Check and Update with Veranda Update's default source (no
# repo= in UPDATE.CFG). It fails unless Update fetched and verified every
# file the list names (doc-samples are never written) and the card then
# holds each one, its size and CRC-32 the list's.
#
# EMU_NET: an x16emu with the Zimodem back-end (-uart ... modem; the
# organisation's x16-emulator, branch modem); ROM (R49).
set -e
cd "$(dirname "$0")/../.."
TOP=$PWD
REL=$(cd "${1:?usage: tools/ci/updcheck.sh <rel-dir> [stable|test]}" && pwd)
CHAN=${2:-stable}
PY="python3 -I -B"
OUT=${UPDCHECK_OUT:-build/updcheck}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
ROM=${ROM:-${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
fail() { echo "FAIL  $*"; exit 1; }
ok() { echo "ok    $*"; }
"$EMU_NET" -h 2>&1 | grep -q -- "modem\[:<options>\]" || fail "$EMU_NET has no -uart modem back-end"
rm -rf "$OUT"
mkdir -p "$OUT/app" "$OUT/srv" "$OUT/card/VERANDA/.SYSTEM"
OUT=$(cd "$OUT" && pwd)
$PY tools/apigen.py api/veranda.api build/gen >/dev/null
$PY tools/kbuild.py >/dev/null
tools/mksdk.sh "$OUT/sdk" >/dev/null
SDK=$OUT/sdk
make -s -C apps/update test SDK="$SDK" OUT="$OUT/app" > "$OUT/app/build.log" 2>&1 || { cat "$OUT/app/build.log"; fail "apps/update's test build"; }
ca65 --cpu 65C02 -I "$SDK/include" -o "$OUT/desk.o" tests/term_desk.s
ld65 -C "$SDK/cfg/app.cfg" -o "$OUT/desk.bin" "$OUT/desk.o"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$OUT/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$OUT/card/VERANDA/SHELL.cvt" "$OUT/desk.hdr" "$OUT/desk.bin" >/dev/null

# the stand-in
printf '{"repo": "veranda-x16/veranda", "release": "%s"}\n' "$REL" > "$OUT/srv/fake.json"
$PY tests/update_fake.py "$OUT/srv" > "$OUT/srv/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for _ in $(seq 50); do [ -f "$OUT/srv/ready" ] && break; sleep 0.1; done
[ -f "$OUT/srv/ready" ] || fail "the GitHub stand-in does not start"
read -r GPORT _ < "$OUT/srv/ready"

# the session: Check, Update (Veranda Update's default repository)
C=$OUT/card
printf 'source=github\r\ngithub=127.0.0.1:%s\r\nchannel=%s\r\n' "$GPORT" "$CHAN" > "$C/VERANDA/.SYSTEM/UPDATE.CFG"
cp "$OUT/app/Update.cvt" "$C/AUTOSTART.cvt"
cp build/VERANDA.PRG build/VERANDA.SYS "$C/"
# Update again after a dropped connection, as a user would (the emulator's
# UART overruns now and then on a loaded machine): what came whole is kept,
# so each try goes on. Up to UPDCHECK_TRIES sessions (default 6) of five
# tries each. A list Veranda Update refuses, a file the release lacks or a
# wrong CRC ends it at once: those are not retried.
echo "run check update update update update update" > "$C/UPDATE.TST"
: > "$OUT/log.txt"
for i in $(seq "${UPDCHECK_TRIES:-6}"); do
	(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 1500 "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "modem:baud=57600,log=$OUT/modem.log" \
		> "$OUT/console.txt" 2>&1) || true
	tr '\r' '\n' < "$OUT/console.txt" > "$OUT/log.$i.txt"
	cat "$OUT/log.$i.txt" >> "$OUT/log.txt"
	grep -a -q "UP END" "$OUT/log.$i.txt" || { grep -a "^UP\|^BOX" "$OUT/log.$i.txt" | tail -20; fail "session $i did not end"; }
	grep -a -q "UP DONE\|UP BADMANIFEST\|UP NOMANIFEST\|does not have it\|CRC" "$OUT/log.$i.txt" && break
	echo "      (session $i: $(grep -a -c 'connection dropped' "$OUT/log.$i.txt") dropped connections; again)"
done
$PY - "$REL/UPDATE.LST" "$C" "$OUT/log.txt" "$OUT/srv/requests.log" "$CHAN" <<'EOF' || { grep -a "^UP\|^BOX" "$OUT/log.txt" | tail -20; exit 1; }
import json, os, sys, zlib
sys.path.insert(0, 'tools')
import mkmanifest
lst, card, log, req, chan = sys.argv[1:]
head, ents = mkmanifest.parse(open(lst, encoding='latin-1').read())
text = open(log, encoding='latin-1', errors='replace').read()
if 'UP DONE %s' % head['build'] not in text:
    sys.exit('FAIL  no "UP DONE %s": Veranda Update did not finish the update' % head['build'])
bad = []
n = 0
for e in ents:
    if e['kind'] == 'doc-sample':
        continue
    p = os.path.join(card, *e['path'].split('/'))
    if not os.path.isfile(p):
        bad.append('%s: not on the card' % e['path'])
        continue
    b = open(p, 'rb').read()
    if len(b) != e['size'] or (zlib.crc32(b) & 0xFFFFFFFF) != e['crc']:
        bad.append('%s: not the release\'s bytes' % e['path'])
    n += 1
if bad:
    sys.exit('FAIL  ' + '; '.join(bad[:10]))
reqs = [json.loads(l) for l in open(req)]
gh = [r for r in reqs if r.get('host') == 'github']
want = '/veranda-x16/veranda/releases/%s' % ('download/test/UPDATE.LST' if chan == 'test' else 'latest/download/UPDATE.LST')
if not any(r.get('path') == want and r.get('status') == 302 for r in gh):
    sys.exit('FAIL  the list was not fetched at %s (%s)' % (want, [r.get('path') for r in gh[:3]]))
bad = [r for r in reqs if r.get('bad') or (r.get('host') == 'github' and r.get('status') != 302)]
if bad:
    sys.exit('FAIL  requests GitHub would refuse or not answer: %s' % bad[:3])
tags = {r.get('tag') for r in gh if r.get('name') != 'UPDATE.LST'}
packed = sum(1 for r in reqs if r.get('host') == 'assets' and r.get('status') == 206)
if 'pack' in head and not packed:
    sys.exit('FAIL  the release has a pack (%s) but no file came from it (V210)' % head['pack'][0])
if tags != {head['tag']}:
    sys.exit('FAIL  the files asked under the tags %s, not %s' % (sorted(tags), head['tag']))
print('ok    Veranda Update installed the release (%s, tag %s, build %s): %d files fetched, verified and in place, '
      'from %s%s' % (chan, head['tag'], head['build'], n, want,
                     ' (V210: %d from the pack %s)' % (packed, head['pack'][0]) if packed else ''))
EOF
echo "UPDCHECK: PASS"
