# (DECISIONS V213) sourced by the network gates: MODEM=real runs a session
# against tests/zimreal.py (Zimodem 4.0.x as its firmware behaves, with a
# Wi-Fi's latency) through the emulator's TCP back-end, in real time (no
# -warp: the latencies are the host's milliseconds), in place of the
# emulator's own modem (which answers at once). ZIMREAL: its options
# (default: tests/zimreal.py's, a loop of 2 ms, a write of 40 ms, a
# connect of 400 ms, a server's bytes 60-140 ms late).
#
#   zim_uart <folder> <the -uart spec>    sets UART (the spec to use), WARP and ZMUL
#                                         (the session's time limit's factor)
#   zim_end                               after the emulator
ZIMPID=
zim_uart() {
	UART=$2
	WARP=-warp
	ZMUL=1
	if [ "$MODEM" = real ] && [ "${2#modem}" != "$2" ]; then
		rm -f "$1/zim.port"
		local ml=${2#*log=}
		[ "$ml" = "$2" ] && ml= || ml=--mlog=${ml%%,*}
		python3 -I -B tests/zimreal.py "$1" $ml $ZIMREAL > "$1/zim.err" 2>&1 &
		ZIMPID=$!
		for _ in $(seq 50); do [ -f "$1/zim.port" ] && break; sleep 0.1; done
		[ -f "$1/zim.port" ] || { echo "FAIL  tests/zimreal.py does not start"; exit 1; }
		UART="tcp:127.0.0.1:$(cat "$1/zim.port")"
		WARP=
		ZMUL=4                  # (the sessions' limits: real time is some 4 times warp's)
	fi
}
zim_end() {
	if [ -n "$ZIMPID" ]; then
		for _ in $(seq 30); do kill -0 "$ZIMPID" 2>/dev/null || break; sleep 0.1; done
		kill "$ZIMPID" 2>/dev/null || true
		wait "$ZIMPID" 2>/dev/null || true
		ZIMPID=
	fi
}
