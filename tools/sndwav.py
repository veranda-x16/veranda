#!/usr/bin/env python3
"""Gate sound (tools/gate_sound.sh, DECISIONS V69): the emulator's recording
of every system sound (tests/sound_script.py wav), cut into one WAV a sound.

usage: sndwav.py <all.wav> <out dir>

The recording has the sounds in id order, each followed by 50 frames of
silence; a cut is made at every silence of 0.4 s or more (the sounds' own
rests are at most 9 frames). Writes <out>/<id>-<name>.wav (with 50 ms of
silence on each side) and checks that there is one piece a sound, each
about its table length, and loud enough (V72): its peak at least half of
one PSG voice at volume 63 (FULL, the emulator's output: a square at 63
peaks at 4088), as the ROM's own bell is a full voice.
"""
import array
import math
import os
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mksounds as ms  # noqa: E402

FRAME = 1 / 59.52               # VERA's 640x480 frame
FULL = 4088                     # one voice at volume 63, a square: its peak in the recording


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    w = wave.open(sys.argv[1], 'rb')
    ch, sw, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
    raw = w.readframes(n)
    w.close()
    if sw != 2:
        sys.exit('sndwav: %d-byte samples' % sw)
    n = len(raw) // (ch * sw)            # (the header's count may be more than was written)
    raw = raw[:n * ch * sw]
    a = array.array('h', raw)
    level = [max(abs(a[i * ch + c]) for c in range(ch)) for i in range(n)]
    quiet = int(0.4 * rate)
    pieces, start, run = [], None, 0
    for i, v in enumerate(level):
        if v > 64:
            if start is None:
                start = i
            run = 0
            last = i
        elif start is not None:
            run += 1
            if run >= quiet:
                pieces.append((start, last + 1))
                start, run = None, 0
    if start is not None:
        pieces.append((start, last + 1))
    os.makedirs(sys.argv[2], exist_ok=True)
    if len(pieces) != len(ms.SOUNDS):
        sys.exit('sndwav: %d sounds in the recording (%s), the table has %d' % (
            len(pieces), ', '.join('%.2f s' % ((b - a) / rate) for a, b in pieces), len(ms.SOUNDS)))
    pad = int(0.05 * rate)
    bad = 0
    for sid, (s, e) in enumerate(pieces, 1):
        name = ms.SOUNDS[sid - 1][0]
        path = os.path.join(sys.argv[2], '%02d-%s.wav' % (sid, name.lower()))
        o = wave.open(path, 'wb')
        o.setnchannels(ch)
        o.setsampwidth(2)
        o.setframerate(rate)
        o.writeframes(raw[max(0, s - pad) * ch * 2:min(n, e + pad) * ch * 2])
        o.close()
        got, want = (e - s) / rate, (ms.frames(sid) - 1) * FRAME
        peak = max(level[s:e])
        rms = math.sqrt(sum(a[i] * a[i] for i in range(s * ch, e * ch)) / ((e - s) * ch))
        okay = abs(got - want) <= 0.06 + 0.1 * want and peak >= FULL // 2
        bad += not okay
        print('%s  %s: %.2f s (the table: %.2f s), peak %d (%.1f dB of a full voice), RMS %.1f dBFS'
              % ('ok   ' if okay else 'FAIL ', path, got, want, peak, 20 * math.log10(peak / FULL),
                 20 * math.log10(max(rms, 1) / 32768)))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
