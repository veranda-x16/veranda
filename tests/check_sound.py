#!/usr/bin/env python3
"""Gate sound (tools/gate_sound.sh, DECISIONS V69): checks tests/sound.s's
console against tools/mksounds.py's table and its model of the player.

usage: check_sound.py <console.txt>

The watch logs PSG voices 15 and 14 whenever they change, from
intFirstVector: at frame f it sees what the sound player wrote in the
interrupt before. The model (mksounds.Player) replays the script's events
at their frames (P: a request, S: the sentinel, R: the settings) and must
give the same registers at every frame of the session. Then, from the same
run: each sound's changes listed; SND_MENU silent by default; Beep equal to
SND_ERROR; every sounding write audible on real VERA (V72: L and R on, a
volume above 0, a pulse at least MIN_PW wide, a triangle's or saw's XOR at
63) and each sound's track A at 60 or more at full volume; the volume
attenuated (blocks saved before V72: full); with the sounds off nothing
written but the alarm; a sound replaced, the alarm not.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mksounds as ms  # noqa: E402

IDS = ms.api_ids()
NAME = {v: k for k, v in IDS.items()}
SENT = (0x1234, 0, 0x3F)
fails = 0


def check(ok, what):
    global fails
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails += 1


def parse(path):
    obs, ev, end = {}, [], None
    for ln in open(path, errors='replace').read().replace('\r', '').split('\n'):
        m = re.search(r'([FPRSE]) ([0-9A-F]{4})((?: [0-9A-F]{2,4})*) ?$', ln)
        if not m:
            continue
        f = [m.group(1), m.group(2)] + m.group(3).split()
        fr = int(f[1], 16)
        if f[0] == 'F' and len(f) == 8:
            v = [int(x, 16) for x in f[2:]]
            obs[fr] = {15: tuple(v[0:3]), 14: tuple(v[3:6])}
        elif f[0] == 'P':
            ev.append((fr, 'P', int(f[2], 16)))
        elif f[0] == 'S':
            ev.append((fr, 'S', None))
        elif f[0] == 'R':
            ev.append((fr, 'R', (int(f[2], 16), int(f[3], 16))))
        elif f[0] == 'E':
            end = fr
    return obs, ev, end


def main():
    obs, ev, end = parse(sys.argv[1])
    if not obs or end is None:
        check(False, 'the session: %d watch lines, end %s' % (len(obs), end))
        return
    f0 = min(obs)
    p = ms.Player({15: list(obs[f0][15]), 14: list(obs[f0][14])})
    cur = dict(obs[f0])
    bad = None
    exp_changes = {}
    last = None
    b15 = 0
    plays = []                  # (frame, id, flags, att, byte 15)
    for f in range(f0, end + 1):
        if f in obs:
            cur = obs[f]
        want = {v: tuple(p.regs[v]) for v in (15, 14)}
        if want != cur and bad is None:
            bad = (f, want, cur, last)
        if want != last:
            exp_changes[f] = want
            last = want
        for fr, k, d in ev:
            if fr != f:
                continue
            if k == 'P':
                p.request(d)
                plays.append((f, d, p.flags, p.att, b15))
            elif k == 'S':
                for v in (15, 14):
                    p.regs[v][:] = list(SENT)
            else:
                p.flags, p.att, b15 = d[0], ms.att(d[1]), d[1]
        p.frame()
    n = len([x for x in ev if x[1] == 'P'])
    if bad:
        f, w, c, _ = bad
        near = [x for x in ev if x[1] == 'P' and x[0] <= f][-1:]
        check(False, 'frame %d (after %s): voices 15/14 %s, the table says %s' % (
            f, ' '.join('%s at %d' % (NAME.get(x[2], x[2]), x[0]) for x in near),
            fmt(c), fmt(w)))
    else:
        check(True, 'PSG voices 15 and 14 at every frame of the session (%d frames, %d requests, %d changes) '
              'as the table and the player\'s model give them' % (end - f0 + 1, n, len(obs)))
    # the findings, each from the run
    def changes(a, b):
        return [(f, obs[f]) for f in sorted(obs) if a < f <= b]

    def span(i):
        a = plays[i][0]
        b = plays[i + 1][0] if i + 1 < len(plays) else end
        return changes(a, b)
    seen = set()
    for i, (f, sid, flags, att, _) in enumerate(plays):
        if flags or att or sid in seen:
            continue
        seen.add(sid)
        c = span(i)
        if sid == IDS['MENU']:
            check(not c, 'SND_MENU with the default settings: nothing written (the menu ticks are off)')
            continue
        dur = (c[-1][0] - f) if c else 0
        check(bool(c) and dur == ms.frames(sid), 'SND_%-8s %3d changes over %2d frames, ending silent: %s'
              % (NAME[sid], len(c), dur, ms.SOUNDS[sid - 1][1]))
    beep = [i for i, x in enumerate(plays) if x[1] == IDS['ERROR'] and not x[2] and not x[3]]
    if len(beep) >= 2:
        a, b = span(beep[0]), span(beep[1])
        check([(f - plays[beep[0]][0], v[15]) for f, v in a] == [(f - plays[beep[1]][0], v[15]) for f, v in b],
              'Beep: voice 15 the same at the same frames as PlaySound(SND_ERROR) (V51\'s beep)')
    tick = [i for i, x in enumerate(plays) if x[1] == IDS['MENU'] and x[2] & 0x40]
    check(bool(tick) and len(span(tick[0])) == 3, 'SND_MENU with the menu ticks on: a 2-frame tick')
    # every write that sounds, as real VERA needs it (V72)
    loud = [(f, v, r) for f in sorted(obs) for v in (15, 14) for r in [obs[f][v]] if r[1] & 63
            and obs[f][v] != SENT]
    bad_w = [(f, v, r) for f, v, r in loud if r[1] & 0xC0 != 0xC0 or ms.audible(r[2], r[1] & 63)]
    check(loud and not bad_w, 'every sounding PSG write (%d) has L and R on, a volume above 0, a pulse '
          '%d-63 wide, a triangle\'s or saw\'s XOR at 63%s' % (len(loud), ms.MIN_PW, ''.join(
              ': frame %d voice %d %s (%s)' % (f, v, '%04X %02X %02X' % r, ms.audible(r[2], r[1] & 63)
                                               or 'L/R off') for f, v, r in bad_w[:3])))
    full = {}
    for i, (f, sid, flags, att, _) in enumerate(plays):
        if not flags and not att and sid != IDS['MENU'] and sid not in full:
            full[sid] = max([v[15][1] & 63 for _, v in span(i)] or [0])
    check(len(full) == len(ms.SOUNDS) - 1 and min(full.values()) >= 60,
          'loud enough: each sound\'s track A at full volume peaks at 60-63 (0 to -1.5 dB of a voice\'s '
          'loudest): %s' % ' '.join('%s %d' % (NAME[k], v) for k, v in sorted(full.items())))
    old = set()
    for i, (f, sid, flags, att, b) in enumerate(plays):
        vols = [v[15][1] & 63 for _, v in span(i)]
        if att == 32 and sid == IDS['STARTUP']:
            check(max(vols) == 63 - 32, 'volume 31 (attenuation 32: -16 dB): SND_STARTUP\'s loudest note at '
                  'volume %d (63 in the table)' % max(vols))
        if att == 32 and sid == IDS['ALARM']:
            check(max(vols) == 63, 'volume 31: the alarm at its own volume (%d)' % max(vols))
        if att == 63 and sid == IDS['WARNING']:
            check(bool(vols) and max(vols) == 0, 'volume 0: SND_WARNING written at volume 0 (%d changes)'
                  % len(vols))
        if sid == IDS['STARTUP'] and not flags and not att and b in (0, 32) and \
                any(x[3] for x in plays[:i]) and (i + 1 == len(plays) or plays[i + 1][0] - f >= ms.frames(sid)):
            old.add(b)
            check(max(vols) == 63, 'a block saved before V72, byte 15 = %d (%s): full volume, SND_STARTUP '
                  'at %d' % (b, 'V56/V65: the user\'s card' if b == 0 else 'V69: a volume of 31, no '
                             'PREFS_VOLSET', max(vols)))
    check(old == {0, 32}, 'blocks saved before V72 played: byte 15 = %s' % sorted(old))
    off = [i for i, x in enumerate(plays) if x[2] & 0x80]
    if off:
        a = plays[off[0]][0]
        al = [i for i in off if plays[i][1] == IDS['ALARM']]
        quiet = changes(a, plays[al[0]][0]) if al else ['?']
        s = [x for x in ev if x[1] == 'S']
        check(not quiet and s and obs.get(max(fr for fr in obs if fr <= a))[15] == SENT,
              'sounds off: %d requests (every sound but the alarm, and Beep): no PSG write, the sentinel '
              'stays in voices 14 and 15' % (len(off) - len(al)))
        check(bool(al) and len(span(al[0])) > 10, 'sounds off: the alarm still sounds (%d changes)'
              % (len(span(al[0])) if al else 0))
    rep = [i for i in range(len(plays) - 1) if plays[i][1] == IDS['STARTUP'] and plays[i + 1][1] == IDS['ERROR']
           and not plays[i][2] and not plays[i][3]]
    if rep:
        i = rep[-1]
        c = span(i + 1)
        check(bool(c) and c[0][1][15][0] == 2362 and c[0][1][14][1] == 0,
              'a new sound replaces the one playing: SND_ERROR 12 frames into the chime, voice 14 silenced')
    alr = [i for i in range(len(plays) - 2) if plays[i][1] == IDS['ALARM'] and plays[i + 1][1] == IDS['ERROR']
           and plays[i + 2][1] == IDS['EXIT'] and not plays[i][2]]
    if alr:
        i = alr[-1]
        c = changes(plays[i][0], plays[i + 3][0])
        check(all(v[15][2] == ms.SQ for _, v in c) and not any(v[15][0] == 2362 for _, v in c),
              'nothing replaces the alarm: SND_ERROR and SND_EXIT during it are dropped')
    print('the model of the player agrees with the kernel at every frame' if not bad else '')


def fmt(r):
    return ' / '.join('%04X %02X %02X' % r[v] for v in (15, 14))


if __name__ == '__main__':
    main()
    sys.exit(1 if fails else 0)
