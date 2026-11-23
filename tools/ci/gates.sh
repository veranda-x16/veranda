#!/bin/bash
# The fast gates of the GitHub workflows (DECISIONS V139): the ones that
# need only the official x16emu and ROM (no GEOS 64 reference, no modem,
# mouse or UART emulator branch), each retried once like tools/release.sh.
#
#   tools/ci/gates.sh [gate ...]      (default: $CI_GATES, else the list below)
#
# EMU, ROM, R49: the emulator and the ROM (tools/ci/setup.sh puts them in
# $CI_TOOLS); logs in $CI_LOGS (default build/ci-gates; not OUT, which each
# gate reads as its own folder and empties). Exits 1 if one fails twice.
set -e
cd "$(dirname "$0")/../.."
DEFAULT="spec boot gfx1 input disk sdk help view shell"
LIST=${*:-${CI_GATES:-$DEFAULT}}
L=${CI_LOGS:-build/ci-gates}
unset OUT GATE_OUT
mkdir -p "$L"
: > "$L/summary.txt"
failed=""
for g in $LIST; do
	case $g in
	spec | boot | gfx1 | gfx | input | ui | disk) c="tools/gate.sh $g" ;;
	*) c="tools/gate_$g.sh" ;;
	esac
	t=$(date +%s)
	res=FAIL
	for try in 1 2; do
		if SDL_VIDEODRIVER=dummy timeout 1800 $c > "$L/$g.$try.log" 2>&1; then
			res=PASS
			break
		fi
	done
	[ $res = PASS ] && [ $try = 2 ] && res=FLAKY
	[ $res = FAIL ] && failed="$failed $g"
	printf '%-8s %-6s %4ss  %s\n' "$g" "$res" "$(( $(date +%s) - t ))" \
		"$(grep -a -m1 'GATE\|^FAIL' "$L/$g.$try.log" | cut -c1-70)" | tee -a "$L/summary.txt"
	[ $res = FAIL ] && tail -15 "$L/$g.2.log" | sed 's/^/    /'
done
[ -z "$failed" ] || { echo "gates: FAILED:$failed (logs in $L)"; exit 1; }
echo "gates: all passed ($LIST)"
