#!/usr/bin/env python3
"""Veranda's system sounds (PlaySound, DECISIONS V69): the table.

usage: mksounds.py <out.inc>

Each sound is one or two tracks: track A on PSG voice 15 (Veranda's, the
beep's, V51), track B on voice 14. A track is a list of notes of 8 bytes:
the frequency word (VERA's: Hz * 2^17 / 48828.125), the waveform byte
(bits 7-6 pulse, sawtooth, triangle, noise; bits 5-0 the pulse width, or
for the triangle and the sawtooth the XOR: 63 the plain wave), the volume
(0-63), the decay (subtracted every frame, down to 0), the length in
frames (1-255; 0 ends the track) and a slide (a signed word added to the
frequency every frame). The player (kernel/g2/sound.s, in the interrupt)
writes a voice's frequency, volume (less the settings' attenuation, both
sides on) and waveform every frame of a note, and frequency 0 and volume 0
the frame after its last note.

Loud enough (V72): VERA's volume is logarithmic, 0.5 dB a step (x16-docs,
VERA Programmer's Reference, "Volume ... with a logarithmic curve"; the
FPGA's psg.v: a log table of 0.5 dB steps), and one voice at its loudest is
1/16 of the DAC's range (16 voices summed; the PCM path, the MOD Player's,
can use all of it). V69's table, written as if the volume were linear
(triangles at 30-50, harmonies at 16-24), sounded 26 to 41 dB below full
scale and 12 to 28 dB below the ROM's own bell (a square at 63): next to
the MOD Player's music on the X16's speakers, nothing. Now track A's
loudest note is at 60-63, pulses are squares (pulse width 63 or near it:
PC/GEOS's PC-speaker sound, and the loudest wave), triangles and saws have
the XOR at 63 (the plain wave), and a note never fades below 30 (-16 dB)
before its end. n() refuses a note against these rules; the gate checks
every register written.

Writes ca65 source: SndTab (two words a sound, ids from 1: track A,
track B or 0) and the tracks. The gates import SOUNDS, frames() and
Player (a model of the player, frame by frame) to check the registers
the kernel writes against this table.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

PULSE, SAW, TRI, NOISE = 0x00, 0x40, 0x80, 0xC0
NOTE = 8                        # bytes a note


def hz(f):
    return int(round(f * 2 ** 17 / 48828.125))


NAMES = 'C C# D D# E F F# G G# A A# B'.split()


def pitch(name):
    """'A5' -> its frequency word (A4 = 440 Hz)"""
    m = re.match(r'^([A-G]#?)(\d)$', name)
    k = NAMES.index(m.group(1)) + 12 * int(m.group(2))
    return hz(440 * 2 ** ((k - NAMES.index('A') - 48) / 12))


MIN_PW = 48                     # a pulse narrower than this is thin and quiet (0: a 1/64 duty)


def audible(wave, vol):
    """the rules of a sounding note (V72): its waveform byte and volume"""
    w, pw = wave & 0xC0, wave & 63
    if w == PULSE and pw < MIN_PW:
        return 'a pulse of width %d (at least %d; 63 a square)' % (pw, MIN_PW)
    if w in (SAW, TRI) and pw != 63:
        return 'a triangle or saw with the XOR at %d (63: the plain wave)' % pw
    if not 0 < vol < 64:
        return 'volume %d' % vol
    return None


def n(f, frames, vol, dec=0, wave=None, slide=0):
    """a note: f a name ('E5') or a frequency word"""
    wave = SQ if wave is None else wave
    w = pitch(f) if isinstance(f, str) else f
    assert 0 <= w < 65536 and 0 <= vol < 64 and 0 <= dec < 64 and 1 <= frames < 256
    assert 0 <= w + slide * (frames - 1) < 65536, 'the slide leaves the range'
    why = audible(wave, vol)
    assert not why, why
    assert vol - dec * (frames - 1) >= 30, 'the note fades below volume 30 (-16 dB) before its end'
    return (w, wave, vol, dec, frames, slide)


def rest(frames):
    return (0, SQ, 0, 0, frames, 0)


SQ = PULSE | 63                 # a square
TRI63 = TRI | 63                # the plain triangle


# id order: api/veranda.api's SND_ constants (checked below)
SOUNDS = [
    ('ERROR', 'the beep (Beep): A5, then E5 fading; 0.27 s, as V51 but a square at full volume',
     [n('A5', 4, 63), n('E5', 12, 63, dec=2)], None),
    ('WARNING', 'a question (a dialog box with YES and NO): E5, a short rest, A5 fading, '
     'with a triangle an octave below; 0.4 s',
     [n('E5', 4, 63), rest(2), n('A5', 18, 63, dec=1)],
     [n('E4', 4, 58, wave=TRI63), rest(2), n('A4', 18, 58, dec=1, wave=TRI63)]),
    ('ALARM', 'the Calendar\'s alarm (its box): three rings of an E6-C6 square-wave trill over '
     'C5; 1.4 s; it sounds with the sounds off, at full volume, and nothing cuts it',
     ([n('E6', 3, 63), n('C6', 3, 63)] * 3 + [rest(9)]) * 3,
     [n('C5', 18, 60, dec=1, wave=TRI63), rest(9)] * 3),
    ('STARTUP', 'the start-up chime (the first desktop after boot or BASIC): C5 E5 G5 rising '
     'to a long C6, over G4 and E5; 1 s',
     [n('C5', 7, 60), n('E5', 7, 60), n('G5', 7, 60), n('C6', 40, 63, dec=0)],
     [rest(7), n('G4', 14, 58, wave=TRI63), n('E5', 40, 58, wave=TRI63)]),
    ('EXIT', 'leaving Veranda (BASIC, Quit Veranda): C6 G5 E5 falling to C5, over E4 and C4; '
     '0.7 s, played to its end before BASIC',
     [n('C6', 6, 60), n('G5', 6, 60), n('E5', 6, 60), n('C5', 24, 63, dec=1)],
     [rest(6), n('E4', 12, 58, wave=TRI63), n('C4', 24, 58, dec=1, wave=TRI63)]),
    ('APP', 'an application starts: a rising sweep G4 to G5 and a tap; 0.2 s',
     [n('G4', 8, 60, dec=1, slide=150), n('G5', 4, 56, dec=2)], None),
    ('OPEN', 'a desk accessory opens: a quick sweep up from C5 and C6; 0.18 s',
     [n('C5', 6, 60, dec=1, slide=280), n('C6', 5, 56, dec=2)], None),
    ('CLOSE', 'a desk accessory closes: the sweep down from C6 and C5; 0.18 s',
     [n('C6', 6, 60, dec=1, slide=-230), n('C5', 5, 56, dec=2)], None),
    ('MENU', 'a menu opens or an item is chosen: a soft 2 kHz tick of two frames '
     '(off unless the settings turn it on)',
     [n(hz(2000), 1, 54), n(hz(2000), 1, 46)], None),
    ('TRASH', 'the trash emptied: a crunch, three falling bursts of noise over a low thud; 0.3 s',
     [n(12000, 3, 63, dec=4, wave=NOISE), rest(2), n(6000, 4, 61, dec=3, wave=NOISE), rest(1),
      n(3000, 9, 60, dec=2, wave=NOISE)],
     [n(hz(110), 7, 63, dec=2, slide=-12)]),
]
ALARM = 3                       # the id the settings do not silence, nothing cuts


def api_ids():
    ids = {}
    for line in open(os.path.join(ROOT, 'api', 'veranda.api')):
        f = [x.strip() for x in line.split('|')]
        if line.startswith('const SND_') and len(f) >= 2:
            ids[f[0].split()[1][4:]] = int(f[1].replace('$', '0x'), 0)
    return ids


def frames(sid):
    """the sound's length in frames (its longer track, and the silence after it)"""
    _, _, a, b = SOUNDS[sid - 1]
    return max(sum(x[4] for x in t) for t in (a, b) if t) + 1


class Player:
    """kernel/g2/sound.s, frame by frame. regs: voice -> [freq, vol byte, wave]
    as the PSG has them (None: not written yet). prefs: the flags (kPrefs:
    bit 7 off, bit 6 menu ticks) and the attenuation (kSndAtt, 0-63, in
    VERA's 0.5 dB volume steps: att(byte 15) gives it from the settings)."""

    def __init__(self, regs=None):
        self.regs = regs or {15: [None, None, None], 14: [None, None, None]}
        self.req = 0
        self.cur = 0
        self.tracks = [None, None]      # [notes, index, left, vol, freq]
        self.flags, self.att = 0, 0
        self.log = []

    def request(self, sid):
        self.req = sid

    def _take(self):
        sid, self.req = self.req, 0
        if sid != ALARM:
            if self.cur == ALARM or self.flags & 0x80 or not 1 <= sid <= len(SOUNDS):
                return
            if sid == api_ids()['MENU'] and not self.flags & 0x40:
                return
        self.cur = sid
        self.log.append(sid)
        _, _, a, b = SOUNDS[sid - 1]
        self.tracks = [[a, 0, 0, 0, 0] if a else None, [b, 0, 0, 0, 0] if b else None]
        for v in (15, 14):              # (both voices silent first)
            self.regs[v][0], self.regs[v][1] = 0, 0

    def frame(self):
        if self.req:
            self._take()
        for i, v in ((0, 15), (1, 14)):
            t = self.tracks[i]
            if not t:
                continue
            notes = t[0]
            if t[2] == 0:
                if t[1] >= len(notes):
                    self.regs[v][0], self.regs[v][1] = 0, 0
                    self.tracks[i] = None
                    continue
                w, wave, vol, dec, ln, sl = notes[t[1]]
                t[2], t[3], t[4] = ln, vol, w
            w, wave, vol, dec, ln, sl = notes[t[1]]
            out = t[3] if self.cur == ALARM else max(0, t[3] - self.att)
            self.regs[v][:] = [t[4], 0xC0 | out, wave]
            t[3] = max(0, t[3] - dec)
            t[4] = (t[4] + sl) & 0xFFFF
            t[2] -= 1
            if t[2] == 0:
                t[1] += 1
        if not any(self.tracks):
            self.cur = 0


def att(b15):
    """the attenuation kernel/s/prefs.s's Apply takes from the settings'
    byte 15 (PREFS_VOLUME, V72): PREFS_VOLSET (bit 7) + 63 - the volume;
    without bit 7 (a file saved before V72) 0: full volume"""
    return b15 & 63 if b15 & 0x80 else 0


def trace(sid, voice=15, start=(0, 0, 0x80), flags=0, att=0):
    """the changes of one voice's registers while sound sid plays from the
    state start (freq, volume byte, waveform): [(frame, (freq, vol, wave))],
    frame 0 the interrupt that takes the request"""
    p = Player({15: list(start), 14: list(start)})
    p.flags, p.att = flags, att
    p.request(sid)
    out, was = [], tuple(start)
    for f in range(frames(sid) + 1):
        p.frame()
        now = tuple(p.regs[voice])
        if now != was:
            out.append((f, now))
            was = now
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ids = api_ids()
    for i, s in enumerate(SOUNDS, 1):
        if ids.get(s[0]) != i:
            sys.exit('mksounds: SND_%s is %s in api/veranda.api, %d here' % (s[0], ids.get(s[0]), i))
    assert ids['ALARM'] == ALARM
    o = ['; generated by tools/mksounds.py: the system sounds (kernel/g2/sound.s)',
         'SND_COUNT = %d' % len(SOUNDS), 'SndTab:']
    for s in SOUNDS:
        o.append('\t.word %s, %s\t; SND_%s' % ('T_%s_A' % s[0], 'T_%s_B' % s[0] if s[3] else 0, s[0]))
    for s in SOUNDS:
        for k, t in (('A', s[2]), ('B', s[3])):
            if not t:
                continue
            o.append('T_%s_%s:' % (s[0], k))
            for w, wave, vol, dec, ln, sl in t:
                o.append('\t.word %d\n\t.byte $%02X, %d, %d, %d\n\t.word %d' % (w, wave, vol, dec, ln, sl & 0xFFFF))
            o.append('\t.byte 0, 0, 0, 0, 0, 0, 0, 0')
    open(sys.argv[1], 'w').write('\n'.join(o) + '\n')


if __name__ == '__main__':
    main()
