#!/usr/bin/env python3
"""Gate bar's mouse scripts (tools/gate_bar.sh; DECISIONS V120): the menu
bar's clock and sound clicked through the X16's real mouse path (the
emulator's -mousescript), on a card in V71's layout, under R49.

usage: bar_script.py <run> <speaker x> > mouse.txt

<speaker x>: the speaker's left (pixels) in the bar, as the gate found it
in a first picture of the bar. The runs (each ends with exit, the pointer
parked at 0, 0 first):
  boot       Veranda started (BASIC: CD, LOAD, RUN), the desktop up
  clock      the clock clicked: Preferences (the Date and Time rows; the
             emulator's clock reads 2000: not set, V127)
  time       then the hour's > once, Return (Save sets the clock), Esc
  typed      (V127) the day picked by the click on the clock: 21 11 2026
             0945 typed, Up (09:46), Return; left open
  now        (V127) the hour's > (pending), Now (the clock's again), Esc
  tick       (V127) the clock set as typed does (09:45), then 70 seconds:
             the rows (not pending) tick; left open
  popup      boot; the sound clicked: the volume pop-up
  volume     then the knob dragged from 63 to 20, Mute, a click outside
  paint      (AUTOSTART: Paint) the clock clicked, Esc; the sound, Esc
  paintclk   (AUTOSTART: Paint) the clock clicked: Preferences over Paint
Frames: 60 a second; "wait 57D n": the kernel's deskNote (DN_CLOCK 1,
DN_VOLUME 2 while Preferences runs, 0 after).
"""
import sys

BOOT = ['180 type DOS"CD:VERANDA"\\n', '300 type LOAD"VERANDA.PRG"\\n', '500 type RUN\\n']
UP = 2600                       # the desktop (or Paint) is up by then


def home(t):
    return ['%d move -200 -200' % (t + f) for f in (0, 4, 8, 12)]


def click(t):
    return ['%d down' % t, '%d up' % (t + 8)]


def end(t):
    return home(t) + ['%d exit' % (t + 60)]


def main():
    run, sx = sys.argv[1], int(sys.argv[2])
    run = 'boot' if run == 'boot2' else run
    out = list(BOOT)
    t = UP
    if run == 'boot':
        out += end(t)
    elif run in ('clock', 'time', 'paintclk', 'paint', 'typed', 'now', 'tick'):
        out += home(t) + ['%d move 600 7' % (t + 40)] + click(t + 60)
        out += ['wait 57D 01', '400 move 0 0']          # Preferences open
        if run in ('time', 'now'):
            # the Time row (9): y 360-375; the hour's > at x 312-327
            # (window 80, 40; CX 184; spin's 16 + 32), Now at 408-455
            out += home(420) + ['460 move 318 367'] + click(480)
            if run == 'time':
                out += ['540 keydown 43', '546 keyup 43']     # Return: Save
            else:
                out += ['540 move 112 0'] + click(560)      # Now
            out += ['620 keydown 110', '626 keyup 110', 'wait 57D 00']
            out += end(120)
        elif run == 'typed':
            out += ['440 type 21112026', '600 type 0945']
            out += ['700 keydown 83', '706 keyup 83']      # Up
            out += ['760 keydown 43', '766 keyup 43']      # Return: Save
            out += end(900)
        elif run == 'tick':
            # (the emulator's clock stands still until it is set, as an
            # X16's never set: set it first)
            out += ['440 type 21112026', '600 type 0945', '760 keydown 43', '766 keyup 43']
            out += end(5000)
        elif run == 'paint':
            out += ['420 keydown 110', '426 keyup 110', 'wait 57D 00']
            out += home(100) + ['140 move %d 7' % (sx + 8)] + click(160)
            out += ['wait 57D 02', '400 move 0 0', '420 keydown 110', '426 keyup 110',
                    'wait 57D 00']
            out += end(120)
        else:
            out += end(420)
    elif run in ('popup', 'volume'):
        out += home(t) + ['%d move %d 7' % (t + 40, sx + 8)] + click(t + 60)
        out += ['wait 57D 02', '400 move 0 0']
        if run == 'volume':
            # the pop-up at x 392 (640 - 240 - 8), y 16: the knob at 63 is
            # x 526-533, y 40-55; 20 is at x 400 + 4 + 40 = 444
            out += home(420) + ['460 move 530 47', '480 down', '490 move -40 0',
                                '500 move -46 0', '520 up']
            out += ['560 move 136 0'] + click(580)      # Mute (x 544-623)
            out += ['640 move -280 250'] + click(660)  # outside: closed, saved
            out += ['wait 57D 00']
            out += end(120)
        else:
            out += end(420)
    else:
        sys.exit('bar_script.py: no run ' + run)
    print('\n'.join(out))


if __name__ == '__main__':
    main()
