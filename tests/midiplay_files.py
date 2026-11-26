#!/usr/bin/env python3
"""gate midiplay (DECISIONS V205): the test songs, made here, and what the
player should do with them.

usage: midiplay_files.py <folder>   writes FMT0.MID, FMT1.MID, SONG.ZSM,
                                    BAD.MID and expect.json into it

FMT0.MID  format 0, 96 ticks a quarter note, 120 BPM: a piano (program 0)
          C4 E4 G4 C5 a beat apart, a bass drum (36) on every beat on
          channel 10, running status throughout, note-offs as note-ons of
          velocity 0
FMT1.MID  format 1, 120 ticks a quarter, three tracks: the conductor (3/4,
          120 BPM, at beat 4 60 BPM), a violin (program 40) with a long note
          (six beats at the slow tempo), a pitch bend, a volume controller;
          drums on channel 10 (36, 38, 42) with running status
SONG.ZSM  ZSM version 1, 60 Hz, no loop: YM2151 channel 0 keyed on at tick
          0 and off at 30, channel 1 on at 60 and off at 90; PSG voice 0
          sounding from tick 0 to 30; the end at 120
BAD.MID   not a MIDI file ("MThd" missing)
More/LOOP.ZSM  SONG.ZSM looping from its start

expect.json: per song the engine's events as the player's log shows them
(kind, channel or note, the frame: 60 a second of the song's time, from
its first event).
MIT licence (see LICENSE)."""
import json
import os
import struct
import sys


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.insert(0, 0x80 | (n & 0x7F))
        n >>= 7
    return bytes(out)


def track(events, running=False):
    """events: (abs tick, bytes with their status) in order; returns the
    MTrk chunk; running: a channel message's status left out when it is the
    one before (running status; meta and sysex events end it)"""
    data = b''
    t = 0
    status = None
    for at, ev in sorted(events, key=lambda e: e[0]):
        if running and ev[0] < 0xF0 and ev[0] == status:
            ev = ev[1:]
        else:
            status = ev[0] if ev[0] < 0xF0 else None
        data += vlq(at - t) + ev
        t = at
    data += vlq(0) + b'\xFF\x2F\x00'
    return b'MTrk' + struct.pack('>I', len(data)) + data


def header(fmt, ntrk, div):
    return b'MThd' + struct.pack('>IHHH', 6, fmt, ntrk, div)


def secs(tick, tempos, div):
    """tick to seconds through the tempo map [(tick, us a quarter)]"""
    s = 0.0
    last_t, us = 0, 500000
    for t, u in tempos:
        if t >= tick:
            break
        s += (t - last_t) * us / div / 1e6
        last_t, us = t, u
    return s + (tick - last_t) * us / div / 1e6


def fmt0():
    div = 96
    ev = [(0, b'\xFF\x51\x03' + (500000).to_bytes(3, 'big')), (0, b'\xC0\x00')]
    notes = [(i * div, n) for i, n in enumerate((60, 64, 67, 72))]
    drums = [(i * div, 36) for i in range(5)]
    for t, n in notes:                  # (note-offs as note-ons of velocity 0)
        ev.append((t, bytes([0x90, n, 100])))
        ev.append((t + 80, bytes([0x90, n, 0])))
    for t, d in drums:
        ev.append((t + 1, bytes([0x99, d, 110])))
        ev.append((t + 21, bytes([0x99, d, 0])))
    data = header(0, 1, div) + track(ev, running=True)
    tempos = [(0, 500000)]
    exp = [('note', n, secs(t, tempos, div)) for t, n in notes]
    exp += [('drum', d, secs(t + 1, tempos, div)) for t, d in drums]
    return data, exp


def fmt1():
    div = 120
    tempos = [(0, 500000), (480, 1000000)]
    cond = [(0, b'\xFF\x58\x04\x03\x02\x18\x08'), (0, b'\xFF\x51\x03' + (500000).to_bytes(3, 'big')),
            (480, b'\xFF\x51\x03' + (1000000).to_bytes(3, 'big'))]
    vio = [(0, b'\xC1\x28'), (0, b'\xB1\x07\x64')]
    notes = [(0, 69, 100), (120, 71, 100), (240, 72, 100), (360, 74, 100), (480, 76, 400 + 720 - 400),
             (1320, 72, 100)]
    for t, n, l in notes:
        vio.append((t, b'\x91' + bytes([n, 96])))
        vio.append((t + l, b'\x81' + bytes([n, 64])))
    vio.append((600, b'\xE1\x00\x48'))      # a pitch bend up, during the long note
    vio.append((900, b'\xE1\x00\x40'))      # and back
    drum = []
    hits = [(0, 36), (120, 42), (240, 38), (360, 42), (480, 36), (600, 42), (720, 38), (840, 42), (960, 36)]
    for t, d in hits:                   # (running status: note-ons, the offs of velocity 0)
        drum.append((t, bytes([0x99, d, 110])))
        drum.append((t + 30, bytes([0x99, d, 0])))
    data = header(1, 3, div) + track(cond) + track(vio) + track(drum, running=True)
    exp = [('note', n, secs(t, tempos, div)) for t, n, l in notes]
    exp += [('drum', d, secs(t, tempos, div)) for t, d in hits]
    return data, exp


def zsm():
    hdr = b'zm' + bytes([1]) + bytes(3) + bytes(3) + bytes([0x03]) + struct.pack('<H', 0x0001) + \
        struct.pack('<H', 60) + bytes(2)
    def ym(pairs):
        out = b''
        while pairs:
            p, pairs = pairs[:63], pairs[63:]
            out += bytes([0x40 + len(p)]) + b''.join(bytes([r, v]) for r, v in p)
        return out

    def voice(ch, kc):
        p = [(0x20 + ch, 0xC7), (0x28 + ch, kc), (0x30 + ch, 0)]
        for op in range(4):
            o = ch + op * 8
            p += [(0x40 + o, 0x01), (0x60 + o, 0x18 if op == 3 else 0x7F), (0x80 + o, 0x1F),
                  (0xA0 + o, 0x00), (0xC0 + o, 0x00), (0xE0 + o, 0x0F)]
        return p
    d = b''
    d += ym(voice(0, 0x4A) + [(0x08, 0x78 | 0)])
    d += bytes([0x00, 0x30, 0x01, 0x0A, 0x02, 0xC0 | 63, 0x03, 0x3F])     # PSG voice 0: frequency, volume, a pulse
    d += bytes([0x80 | 30])
    d += ym([(0x08, 0x00)]) + bytes([0x02, 0xC0])
    d += bytes([0x80 | 30])
    d += ym(voice(1, 0x3E) + [(0x08, 0x78 | 1)])
    d += bytes([0x80 | 30])
    d += ym([(0x08, 0x01)])
    d += bytes([0x80 | 30])
    d += b'\x80'
    exp = [('kon', 0, 0x78, 0), ('psg', 0, 63, 0), ('kon', 0, 0, 30), ('psg', 0, 0, 30),
           ('kon', 1, 0x78, 60), ('kon', 1, 0, 90)]
    return hdr + d, exp


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    exp = {}
    for name, f in (('FMT0.MID', fmt0), ('FMT1.MID', fmt1), ('SONG.ZSM', zsm)):
        data, e = f()
        open(os.path.join(out, name), 'wb').write(data)
        exp[name] = e
    # More/LOOP.ZSM: SONG.ZSM looping from its first event (the loop point
    # at offset 16, the data's start)
    data, e = zsm()
    os.makedirs(os.path.join(out, 'More'), exist_ok=True)
    open(os.path.join(out, 'More', 'LOOP.ZSM'), 'wb').write(data[:3] + bytes([16, 0, 0]) + data[6:])
    exp['LOOP.ZSM'] = e
    open(os.path.join(out, 'BAD.MID'), 'wb').write(b'RIFF' + bytes(60))
    json.dump(exp, open(os.path.join(out, 'expect.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
