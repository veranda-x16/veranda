#!/usr/bin/env python3
"""gate midiplay (DECISIONS V205): MIDI Player's test sessions read back.

usage: check_midiplay.py host <console.txt> <expect.json>
       check_midiplay.py doc <console.txt>
       check_midiplay.py wav <console.txt> <song.wav>

host: the playlist, the refused file, every note and drum of FMT0.MID and
FMT1.MID and every key-on and PSG volume of SONG.ZSM at its frame (60 a
second of the song's time, from the song's first event; within one
frame), the pause (nothing played, the time held, every voice off),
Play next, the stop after the last song, the volume, Alt+Tab (aside,
back, going on), the quit; the tick's cycles: the most under a frame,
no tick later than 1.5 frames after the one before while a song plays.

wav: the emulator's recording from the song's start: sound while
FMT1.MID plays, silence while it is paused and after Stop, sound while
SONG.ZSM plays, silence after the quit.
MIT licence (see LICENSE)."""
import array
import json
import re
import sys
import wave

FRAME_CYC = 8000000 / 59.94     # a frame's cycles at 8 MHz


def lines(path):
    t = open(path, 'rb').read().decode('latin-1').replace('\r', '\n')
    out = []
    for ln in t.split('\n'):
        for m in re.finditer(r'(MP [^\x00-\x1f\x80-\xff]*|TERMDESK[ A-Z]*)', ln):
            out.append(m.group(1).rstrip())
    return out


def fail(msg):
    sys.exit('FAIL  ' + msg)


def ok(msg):
    print('ok    ' + msg)


def num(ls, key):
    for ln in ls:
        if ln.startswith(key):
            return int(ln[len(key):].split()[0])
    fail('no "%s" in the console' % key)


def sections(ls):
    """the events of each song played: [(name, [(kind, ch, note, frame)])]"""
    out, cur = [], None
    for ln in ls:
        m = re.match(r'MP PLAY (MIDI|ZSM)(.*)', ln)
        if m:
            cur = (m.group(2).strip(), [])
            out.append(cur)
            continue
        m = re.match(r'MP EV ([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{4})', ln)
        if m and cur:
            cur[1].append(tuple(int(g, 16) for g in m.groups()))
    return out


def unwrap(evs):
    """the stop's releases of the song before (logged after the new one's
    start) left out"""
    k = 0
    while k < len(evs) and evs[k][0] == 3:
        k += 1
    return evs[k:]


def match(name, got, want, tol=1):
    """want: [(kind, key, frame)], got [(kind, key, frame)]: one to one, in
    frames from the first's, within tol"""
    if not got:
        fail('%s: no events logged' % name)
    f0 = min(f for k, x, f in got)
    w0 = min(f for k, x, f in want)
    left = [(k, x, f - f0) for k, x, f in got]
    worst = 0
    for k, x, f in sorted(want, key=lambda e: e[2]):
        f -= w0
        best = None
        for i, (gk, gx, gf) in enumerate(left):
            if gk == k and gx == x and abs(gf - f) <= tol and (best is None or abs(gf - f) < abs(left[best][2] - f)):
                best = i
        if best is None:
            fail('%s: %s %d at frame %.1f not played (got %s)' % (name, k, x, f, sorted(left, key=lambda e: e[2])[:12]))
        worst = max(worst, abs(left[best][2] - f))
        del left[best]
    if left:
        fail('%s: played more than the file has: %s' % (name, left[:8]))
    return worst


def host(console, expect):
    ls = lines(console)
    exp = json.load(open(expect))
    if 'MP SESSION host' not in ls:
        fail('the session did not start')
    lst = [ln[8:] for ln in ls if ln.startswith('MP LIST ')]
    want = ['U..', 'DMore', 'MBAD.MID', 'MFMT0.MID', 'MFMT1.MID', 'ZSONG.ZSM']
    if lst != want:
        fail('the playlist: %s (want %s)' % (lst, want))
    ok('the playlist of MUSIC: .., the folder, three MIDI files, the ZSM, sorted')
    if num(ls, 'MP ERR ') != 5:
        fail('BAD.MID: error %d (want 5, not a MIDI file)' % num(ls, 'MP ERR '))
    ok('BAD.MID refused: "Not a MIDI file it can play"')
    secs = sections(ls)
    names = [s[0] for s in secs]
    if names[:6] != ['FMT0.MID', 'FMT1.MID', 'SONG.ZSM', 'FMT0.MID', 'LOOP.ZSM', 'FMT1.MID']:
        fail('the songs played: %s' % names)
    ok('Play next: FMT0.MID, then FMT1.MID, then SONG.ZSM by themselves')
    worst = 0
    for name, evs in secs[:2]:
        ev = unwrap(evs)
        got = [('note' if k == 1 else 'drum', n, f) for k, c, n, f in ev if k in (1, 2)]
        w = [(k, n, s * 1e6 / 16667) for k, n, s in exp[name]]
        worst = max(worst, match(name, got, w))
        rel = [(k, c) for k, c, n, f in ev if k == 3]
        ons = [c for k, c, n, f in ev if k in (1, 2)]
        if len(rel) < len(ons):
            fail('%s: %d notes, %d releases' % (name, len(ons), len(rel)))
    ok('FMT0.MID (format 0, running status, drums on channel 10) and FMT1.MID (format 1, 3 tracks, a tempo '
       'change, a long note, pitch bend): every note and drum at its frame (the worst %d frame off), each released'
       % worst)
    ev = unwrap(secs[2][1])
    got = [('kon' if k == 4 else 'psg', (c, n), f) for k, c, n, f in ev if k in (4, 5)]
    w = [(k, (c, v), t) for k, c, v, t in exp['SONG.ZSM']]
    wz = match('SONG.ZSM', got, w)
    ok('SONG.ZSM (ZSMKit): YM2151 channels 0 and 1 keyed on and off and PSG voice 0 at their ticks (the worst %d off)' % wz)
    # the pause
    i0 = ls.index(next(l for l in ls if l.startswith('MP PAUSE AT ')))
    i1 = ls.index(next(l for l in ls if l.startswith('MP RESUME AT ')))
    mid = [l for l in ls[i0:i1] if l.startswith('MP EV 01') or l.startswith('MP EV 02')]
    if mid:
        fail('notes played while paused: %s' % mid)
    if num(ls, 'MP PAUSE AT ') != num(ls, 'MP RESUME AT '):
        fail('the time went on while paused')
    v = [l for l in ls[i0:i1] if l.startswith('MP VOICES ON ')]
    if v != ['MP VOICES ON 0']:
        fail('paused: voices still on: %s' % v)
    ok('paused a second at frame %d: no notes, every YM2151 channel and PSG voice off, the time held' % num(ls, 'MP PAUSE AT '))
    i = ls.index('MP STOP')
    if ls[i - 1] != 'MP SONG END' or 'MP VOICES ON 0' not in ls[i:i + 3]:
        fail('after the last song: %s' % ls[i - 2:i + 3])
    ok('the last song ended: stopped (Play next does not wrap), every voice off')
    if num(ls, 'MP VOLUME ') != 9:
        fail('the volume: %d (want 9)' % num(ls, 'MP VOLUME '))
    ok('the volume: 10, down twice, up once: 9')
    rep = [c for k, c, n, f in secs[3][1] if k == 1 and n == 60]
    if 'MP REPEAT' not in ls or len(rep) != 2 or num(ls, 'MP REPEAT FRAMES ') >= 150:
        fail('Repeat: FMT0.MID\'s first note played %d times, "MP REPEAT" %s' % (len(rep), 'MP REPEAT' in ls))
    ok('Repeat on: FMT0.MID played again from its start at its end')
    lp = [(c, n) for k, c, n, f in secs[4][1] if k == 4 and n]
    i = ls.index('MP PLAY ZSMLOOP.ZSM') if 'MP PLAY ZSMLOOP.ZSM' in ls else ls.index('MP PLAY ZSM LOOP.ZSM')
    tail = [l for l in ls[i:] if not l.startswith('MP EV')][:4]
    if len(lp) < 3 or 'MP SONG END' not in tail or 'MP STOP' not in tail:
        fail('LOOP.ZSM: %d key-ons, then %s' % (len(lp), tail))
    t = num(ls, 'MP LOOP TICKS ')
    ok('a ZSM that loops (More/LOOP.ZSM, Play next on): round once, again while it fades, %d key-ons, ended after '
       '%.1f s, stopped (the folder\'s last song)' % (len(lp), t / 59.94))
    for k in ('MP ASIDE', 'TERMDESK WAITED', 'MP BACK'):
        if k not in ls:
            fail('Alt+Tab: no "%s"' % k)
    if not ls.index('MP ASIDE') < ls.index('TERMDESK WAITED') < ls.index('MP BACK'):
        fail('Alt+Tab: out of order')
    ia, ib = ls.index('MP ASIDE'), ls.index('MP BACK')
    aside_notes = [l for l in ls[ia:ib] if l.startswith('MP EV 01') or l.startswith('MP EV 02')]
    if aside_notes:
        fail('notes played while aside: %s' % aside_notes)
    after = [l for l in ls[ib:] if l.startswith('MP EV 01') or l.startswith('MP EV 02')]
    if not after or num(ls, 'MP ON AFTER ') < 120:
        fail('the music did not go on after Alt+Tab')
    ok('Alt+Tab at frame %d: paused while aside (3 s on the test desktop), going on when back (%d notes after)'
       % (num(ls, 'MP ASIDE AT '), len(after)))
    if 'MP QUIT' not in ls:
        fail('no quit')
    cmax, csum, cn, gap = num(ls, 'MP CYC MAX '), num(ls, 'MP CYC SUM '), num(ls, 'MP CYC TICKS '), num(ls, 'MP GAP MAX ')
    if cmax >= FRAME_CYC / 2:
        fail('a tick took %d cycles' % cmax)
    if gap > 1.5 * FRAME_CYC:
        fail('a tick came %d cycles after the one before (a frame is %d)' % (gap, FRAME_CYC))
    ok('the tick: %d ticks, %d cycles on average (%.1f %% of a frame at 8 MHz), %d at most (%.1f %%); the longest '
       'gap between two ticks while playing %d cycles (%.2f frames: none missed; the window body drawn %d times meanwhile, in %d frames)'
       % (cn, csum // cn, 100.0 * csum / cn / FRAME_CYC, cmax, 100.0 * cmax / FRAME_CYC, gap, gap / FRAME_CYC,
          num(ls, 'MP REDRAWS '), num(ls, 'MP STRESS TO ') - num(ls, 'MP STRESS FROM ')))


def rms(a, rate, t0, t1):
    i0, i1 = int(t0 * rate) * 2, int(t1 * rate) * 2
    s = a[max(0, i0):max(0, i1)]
    if not s:
        return 0.0
    return (sum(x * x for x in s) / len(s)) ** 0.5


def wav(console, path):
    ls = lines(console)
    w = wave.open(path, 'rb')
    rate = w.getframerate()
    if w.getnchannels() != 2 or w.getsampwidth() != 2:
        fail('wav: %d channels of %d bytes' % (w.getnchannels(), w.getsampwidth()))
    a = array.array('h', w.readframes(w.getnframes()))
    dur = w.getnframes() / rate
    t = {k: num(ls, 'MP T %s ' % k) for k in ('PLAY', 'PAUSE', 'RESUME', 'STOP', 'ZSM', 'ZSM END', 'QUIT')}
    hz = 59.94
    s = {k: (v - t['PLAY']) / hz for k, v in t.items()}
    checks = [('FMT1.MID playing', 0.3, s['PAUSE'] - 0.1, True),
              ('paused', s['PAUSE'] + 0.8, s['RESUME'] - 0.1, False),
              ('playing again', s['RESUME'] + 0.3, s['STOP'] - 0.1, True),
              ('stopped', s['STOP'] + 0.8, s['ZSM'] - 0.05, False),
              ('SONG.ZSM playing', s['ZSM'] + 0.1, s['ZSM'] + 0.45, True),
              ('after the quit', s['QUIT'] + 0.8, min(dur, s['QUIT'] + 2.5), False)]
    out = []
    for what, a0, a1, sound in checks:
        if a1 - a0 < 0.2:
            fail('wav: %s: the window %.2f-%.2f s is too short (the recording %.1f s)' % (what, a0, a1, dur))
        r = rms(a, rate, a0, a1)
        if sound and r < 300:
            fail('wav: %s (%.1f-%.1f s): RMS %.0f, no sound' % (what, a0, a1, r))
        if not sound and r > 30:
            fail('wav: %s (%.1f-%.1f s): RMS %.0f, not silent' % (what, a0, a1, r))
        out.append('%s %.0f' % (what, r))
    ok('wav (%.1f s at %d Hz, RMS from the song\'s start): %s' % (dur, rate, ', '.join(out)))


def doc(console):
    ls = lines(console)
    for k in ('MP SESSION doc', 'MP DOCUMENT FMT0.MID', 'MP DOC FOLDER /MUSIC', 'MP DOC PLAYING FMT0.MID',
              'MP DOC SELECTED 1', 'MP QUIT'):
        if k not in ls:
            fail('doc: no "%s" (%s)' % (k, [l for l in ls if not l.startswith('MP EV')][:12]))
    if not any(l.startswith('MP EV 01 07 3C') for l in ls):
        fail('doc: FMT0.MID\'s first note not played')
    ok('a document: FMT0.MID opened as the shell opens it (its folder /MUSIC the playlist, the song chosen), playing')


def main():
    if sys.argv[1] == 'doc':
        doc(sys.argv[2])
    elif sys.argv[1] == 'host':
        host(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'wav':
        wav(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
