#!/usr/bin/env python3
"""gate midiplay (DECISIONS V205, V206): MIDI Player's test sessions read back.

usage: check_midiplay.py host <console.txt> <expect.json>
       check_midiplay.py screens <console.txt> <expect.json> <folder of DEMO.RAW, DARK.RAW>
       check_midiplay.py doc <console.txt>
       check_midiplay.py dock <console.txt>
       check_midiplay.py wav <console.txt> <song.wav>

host: the playlist, the refused file, every note and drum of FMT0.MID and
FMT1.MID and every key-on and PSG volume of SONG.ZSM at its frame (60 a
second of the song's time, from the song's first event; within one
frame), the pause (nothing played, the time held, every voice off),
Play next, the stop after the last song, the volume, Alt+Tab (aside,
back, going on), the quit; the tick's cycles: the most under a frame,
no tick later than 1.03 frames after the one before while a song plays;
the window's work in the main loop (V206: its cycles a second).

screens (V206): More/DEMO.MID's pictures (tests/midiplay_play.c's
DEMO.RAW, DARK.RAW: the bitmap, the colour map, the palette): exactly the
keys of the notes sounding then lit, each in a voice's colour whose meter
is lit in it; the FM meters of five voices lit; its channels 1-3 and 10
marked, the others not; the lyrics' highlight; its title, text and length
read from the file; dark mode: the ink light, the white keys ink.
(V208) NEXT.RAW, NEXTDK.RAW: More/DESERT.MID (no name, no text, no lyrics)
by Play next after DEMO.MID: now playing's layout in all four pictures
(the display's top border whole, no text touching it, one progress bar,
"of m:ss" apart from the big digits), DESERT.MID's blank rows blank.

dock (V206): started as from the dock in /VERANDA/APPS, ".." up to the
card's top and no further.

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
GAP_MAX = 1.03                  # (frames) the latest a tick may come after the one before


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
    if names[:10] != ['FMT0.MID', 'FMT1.MID', 'SONG.ZSM', 'FMT0.MID', 'LOOP.ZSM', 'DEMO.MID', 'DESERT.MID', 'DEMO.MID',
                      'DESERT.MID', 'FMT1.MID']:
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
    if gap > GAP_MAX * FRAME_CYC:
        fail('a tick came %d cycles (%.3f frames) after the one before' % (gap, gap / FRAME_CYC))
    ok('the tick: %d ticks, %d cycles on average (%.1f %% of a frame at 8 MHz), %d at most (%.1f %%); the longest '
       'gap between two ticks while playing %d cycles (%.3f frames: none missed; the window body drawn %d times meanwhile, in %d frames)'
       % (cn, csum // cn, 100.0 * csum / cn / FRAME_CYC, cmax, 100.0 * cmax / FRAME_CYC, gap, gap / FRAME_CYC,
          num(ls, 'MP REDRAWS '), num(ls, 'MP STRESS TO ') - num(ls, 'MP STRESS FROM ')))
    umax, usum, un, span = num(ls, 'MP UI MAX '), num(ls, 'MP UI SUM '), num(ls, 'MP UI N '), num(ls, 'MP UI SPAN ')
    if not un:
        fail('the window\'s updates were not counted')
    ok('the window (V206: the meters, the keyboard, the display; 20 updates a second while a song plays): %d updates, '
       '%d cycles each on average (%.1f %% of the CPU at 20 a second), %d at most (%.2f frames)'
       % (un, usum // un, 100.0 * (usum / un) * 20 / 8000000, umax, umax / FRAME_CYC))


# the keyboard (apps/midiplay/vis.c): its first card, C2 = 36, the octave's
# 14 cards (white keys 2, black keys 1: card rows 49-52; white keys' lower
# part: card rows 53-56)
KB_C0, KB_LO, KB_N = 4, 36, 61
K_BLACK = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
K_COL = [0, 1, 2, 4, 4, 6, 7, 8, 9, 10, 12, 12]
VCOL = [8, 13, 10, 9, 6, 11, 7, 15]     # GREEN SKY2 ORANGE PURPLE YELLOW CYAN RED DUSK
PAPER, CHROME = 0, 2


def raw(path):
    d = open(path, 'rb').read()
    bits, cards, pal = d[:38400], d[38400:43200], d[43200:43232]
    return bits, cards, [pal[2 * i] | pal[2 * i + 1] << 8 for i in range(16)]


def key_probe(n):
    i = n - KB_LO
    s, o = i % 12, i // 12
    c = KB_C0 + 14 * o + K_COL[s]
    return (c, 50) if K_BLACK[s] else (c, 54)


def screen(name, path, want, dark):
    bits, cards, pal = raw(path)
    card = lambda c, r: cards[r * 80 + c] & 15
    ink = lambda x, y: bool(bits[y * 80 + (x >> 3)] & (0x80 >> (x & 7)))
    lum = lambda c: (c >> 8 & 15) * 3 + (c >> 4 & 15) * 6 + (c & 15)
    if dark != (lum(pal[1]) > lum(pal[0])):
        fail('%s: the palette is not %s mode (paper %03X, ink %03X)' % (name, 'dark' if dark else 'light', pal[0], pal[1]))
    base = CHROME if dark else PAPER
    lit = {}
    for n in range(KB_LO, KB_LO + KB_N):
        c = card(*key_probe(n))
        if c != base:
            lit[n] = c
    if sorted(lit) != sorted(want):
        fail('%s: the keys lit %s (want %s)' % (name, sorted(lit), sorted(want)))
    meters = {}
    for v in range(8):
        c = card(23, 31 + 2 * v)
        if c != CHROME:
            meters[v] = c
        if c not in (CHROME, VCOL[v]):
            fail('%s: FM voice %d\'s meter in colour %d' % (name, v + 1, c))
    for n, c in lit.items():
        if c not in VCOL or VCOL.index(c) not in meters:
            fail('%s: key %d in colour %d, no FM voice of that colour sounding (meters %s)' % (name, n, c, meters))
    if len(meters) < 5:
        fail('%s: %d FM meters lit (want 5 at least: the piano\'s three, the bass, the flute)' % (name, len(meters)))
    used = [ch for ch in range(16) if card(49 + 16 * (ch >> 3), 31 + 2 * (ch & 7)) != PAPER]
    if used != [0, 1, 2, 9]:
        fail('%s: the MIDI channels marked %s (want 1, 2, 3, 10)' % (name, [u + 1 for u in used]))
    hl = card(36, PROG_ROW)             # (the progress bar's first card: the highlight)
    if hl in (PAPER, CHROME) or not any(card(c, LYR_Y >> 3) == hl for c in range(43, 80)):
        fail('%s: the lyrics\' newest syllable not highlighted' % name)
    # the white keys' pixels: paper in light mode, ink in dark (D2's lower part)
    if ink(KB_C0 * 8 + 2 * 8 + 8, 440) != dark:
        fail('%s: a white key drawn %s' % (name, 'paper' if dark else 'ink'))
    return lit, meters


# now playing's layout (apps/midiplay/now.c, V208)
RX, RR, TOP_Y, LINE_H = 288, 631, 72, 14
LCD_T, LCD_B, COL_A, BIG_Y, BIG_H = 120, 175, 38, 137, 20
PROG_COL, PROG_W, PROG_ROW, LYR_Y = 36, 43, 24, 208


def layout(name, path, blank):
    """now playing: the display's top border whole (no text across it, a
    clear row above it and below its dotted shade), one progress bar, the
    "of m:ss" line apart from the big digits; blank: the song has no
    second line and no lyrics (after a song that had both): those rows
    empty, no highlight left. Returns the "of" line's gap."""
    bits, cards, pal = raw(path)
    card = lambda c, r: cards[r * 80 + c] & 15
    ink = lambda x, y: bool(bits[y * 80 + (x >> 3)] & (0x80 >> (x & 7)))
    row_ink = lambda y, x0=RX, x1=RR: [x for x in range(x0, x1 + 1) if ink(x, y)]
    if len(row_ink(LCD_T, RX + 2, RR - 2)) != RR - RX - 3:
        fail('%s: the display\'s top border (line %d) not whole' % (name, LCD_T))
    if any(ink(x, LCD_T + 1) != (x % 2 == 0) for x in range(RX + 2, RR - 1)):
        fail('%s: the display\'s dotted shade (line %d) crossed' % (name, LCD_T + 1))
    for y in list(range(LCD_T - 4, LCD_T)) + [LCD_T + 2]:
        if row_ink(y, RX + 4, RR - 4):
            fail('%s: text touching the display\'s top border (line %d)' % (name, y))
    # one progress bar: between the display and the lyrics only its frame
    top, bot = PROG_ROW * 8 - 1, PROG_ROW * 8 + 8
    x0, x1 = PROG_COL * 8 - 1, (PROG_COL + PROG_W) * 8
    for y in range(LCD_B + 1, LYR_Y):
        got = row_ink(y, RX - 1, RR + 1)
        want = list(range(x0, x1 + 1)) if y in (top, bot) else [x0, x1] if top < y < bot else []
        if got != want:
            fail('%s: line %d between the display and the lyrics: ink at %d pixels (want only one progress bar\'s '
                 'frame)' % (name, y, len(got)))
    for r in range((LCD_B + 1) >> 3, LYR_Y >> 3):
        cols = {card(c, r) for c in range(PROG_COL, PROG_COL + PROG_W)}
        if r != PROG_ROW and cols != {PAPER}:
            fail('%s: card row %d (not the progress bar\'s) in colours %s' % (name, r, sorted(cols)))
    # the time's column: the big digits, then (a gap) "of m:ss" inside the display
    rows = [y for y in range(LCD_T + 3, LCD_B) if row_ink(y, COL_A * 8, COL_A * 8 + 55)]
    runs = []
    for y in rows:
        if runs and y == runs[-1][1] + 1:
            runs[-1][1] = y
        else:
            runs.append([y, y])
    if len(runs) != 3 or runs[1] != [BIG_Y, BIG_Y + BIG_H - 1]:
        fail('%s: the time\'s column: ink in lines %s (want the label, the big digits at %d-%d, "of m:ss")'
             % (name, runs, BIG_Y, BIG_Y + BIG_H - 1))
    gap = runs[2][0] - runs[1][1] - 1
    if gap < 2 or runs[2][1] > LCD_B - 3:
        fail('%s: "of m:ss" at lines %d-%d: %d blank lines under the big digits (want 2 at least), the '
             'display\'s bottom at %d' % (name, runs[2][0], runs[2][1], gap, LCD_B))
    if blank:
        for y in list(range(TOP_Y + LINE_H, TOP_Y + 2 * LINE_H)) + list(range(LYR_Y, LYR_Y + 16)):
            if row_ink(y, RX - 1, 639):
                fail('%s: line %d not blank (the song before\'s second line or lyrics left)' % (name, y))
        for r in (LYR_Y >> 3, (LYR_Y >> 3) + 1):
            if {card(c, r) for c in range(RX >> 3, (RR >> 3) + 1)} != {PAPER}:
                fail('%s: the lyrics\' row %d still coloured (a highlight left)' % (name, r))
    return gap


def screens(console, expect, folder):
    ls = lines(console)
    exp = json.load(open(expect))
    want = exp['DEMO_KEYS']
    at = num(ls, 'MP DEMO SNAP AT '), num(ls, 'MP DARK SNAP AT ')
    if not (30 <= at[0] < 236 and 30 <= at[1] < 236):
        fail('DEMO.MID\'s pictures at frames %d and %d, outside 30-236 (where its notes are known)' % at)
    lit, meters = screen('DEMO.RAW', folder + '/DEMO.RAW', want, False)
    screen('DARK.RAW', folder + '/DARK.RAW', want, True)
    ok('More/DEMO.MID at frame %d (light) and %d (dark mode): exactly the keys of C2 C4 E4 G4 E5 lit, each in its '
       'voice\'s colour (%s), %d FM meters lit, channels 1, 2, 3 and 10 marked, the lyrics\' newest syllable '
       'highlighted; dark mode: the ink light, the white keys ink'
       % (at[0], at[1], ', '.join('%d: %d' % (n, c) for n, c in sorted(lit.items())), len(meters)))
    gaps = [layout(n, folder + '/' + n, False) for n in ('DEMO.RAW', 'DARK.RAW')]
    for n, dark in (('NEXT.RAW', False), ('NEXTDK.RAW', True)):
        gaps.append(layout(n, folder + '/' + n, True))
        bits, cards, pal = raw(folder + '/' + n)
        lum = lambda c: (c >> 8 & 15) * 3 + (c >> 4 & 15) * 6 + (c & 15)
        if dark != (lum(pal[1]) > lum(pal[0])):
            fail('%s: not in %s mode' % (n, 'dark' if dark else 'light'))
        used = [ch for ch in range(16) if cards[(31 + 2 * (ch & 7)) * 80 + 49 + 16 * (ch >> 3)] & 15 != PAPER]
        if used != [1, 2, 3, 4, 5]:
            fail('%s: the MIDI channels marked %s (want 2-6)' % (n, [u + 1 for u in used]))
    t = [next((l[len(k):].strip() for l in ls if l.startswith(k)), None) for k in ('MP NEXT TITLE', 'MP NEXT TEXT')]
    if t != ['', ''] or num(ls, 'MP NEXT SECS ') != exp['DESERT_SECS']:
        fail('DESERT.MID read through: title %r, text %r, %d s (want none, none, %d s)'
             % (t[0], t[1], num(ls, 'MP NEXT SECS '), exp['DESERT_SECS']))
    ok('now playing (V208): the display\'s top border whole and clear of the text, one progress bar, "of m:ss" '
       '%d blank lines under the big digits (DEMO.MID light and dark); More/DESERT.MID (format 0, no name, no '
       'copyright, no lyrics, %d:%02d) by Play next after DEMO.MID, in dark mode (frame %d) and light (frame %d): '
       'its second line and the lyrics\' rows blank, no highlight left, channels 2-6 marked'
       % (min(gaps), exp['DESERT_SECS'] // 60, exp['DESERT_SECS'] % 60, num(ls, 'MP NEXTDK SNAP AT '),
          num(ls, 'MP NEXT SNAP AT ')))
    title = next((l[len('MP DEMO TITLE '):] for l in ls if l.startswith('MP DEMO TITLE ')), None)
    text = next((l[len('MP DEMO TEXT '):] for l in ls if l.startswith('MP DEMO TEXT ')), None)
    secs = num(ls, 'MP DEMO SECS ')
    if title != 'Veranda Demo' or text != 'MIDI Player gate, CC0' or secs != 8:
        fail('DEMO.MID read through: title %r, text %r, %d s (want "Veranda Demo", "MIDI Player gate, CC0", 8 s)'
             % (title, text, secs))
    ok('DEMO.MID read through at its start: its title "%s" (the first track\'s name), its text "%s" (the copyright), '
       'its length %d s (four bars of 4/4 at 120 BPM)' % (title, text, secs))


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


def dock(console):
    ls = lines(console)
    for k in ('MP SESSION dock', 'MP DOCK FOLDER /VERANDA/APPS', 'MP QUIT'):
        if k not in ls:
            fail('dock: no "%s" (%s)' % (k, [l for l in ls if not l.startswith('MP EV')][:16]))
    ups = [l[len('MP DOCK UP '):] for l in ls if l.startswith('MP DOCK UP ')]
    if ups != ['/VERANDA', '/', '/']:
        fail('dock: up from /VERANDA/APPS: %s (want /VERANDA, /, / again)' % ups)
    lst = [l[len('MP DOCK LIST '):] for l in ls if l.startswith('MP DOCK LIST ')]
    if 'U..' in lst or 'DMUSIC' not in lst or 'DVERANDA' not in lst:
        fail('dock: the card\'s top listed as %s' % lst)
    ok('from the dock: /VERANDA/APPS shown, ".." to /VERANDA, ".." to the card\'s top "/" (no "..", %s), ".." '
       'again stays there' % ', '.join(l[1:] for l in lst))


def main():
    if sys.argv[1] == 'doc':
        doc(sys.argv[2])
    elif sys.argv[1] == 'dock':
        dock(sys.argv[2])
    elif sys.argv[1] == 'screens':
        screens(sys.argv[2], sys.argv[3], sys.argv[4])
    elif sys.argv[1] == 'host':
        host(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'wav':
        wav(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
