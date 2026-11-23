#!/usr/bin/env python3
"""Gate about (DECISIONS V119): About this X16's console ("AB ...") against
what the host knows.

usage: check_about.py <session> <console.txt> <rom.bin> <ram KB> [<sd.img> | <modem.log> | <run folder>]
  host   512 KB, the host folder: every value; a second of live updates;
         Copy (the Text Scrap in the run folder's VERANDA/.SYSTEM); Ask the
         modem with no card; Alt+Tab: back with AbHelper aside (its banks
         among the programs aside, the free banks fewer by as many)
  plain  the values at another RAM size (2 MB), or on an SD card image
         (its name, size and free space against the image)
  modem  the modem emulator: the UART at $9FE0, the firmware's line from
         ATI; the modem's log: AT and ATI only (nothing that changes it)
"""
import os
import re
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def ok(msg):
    print('ok    ' + msg)


def ui_size(v):
    def tenths(v, sh, unit):
        w = v >> sh
        d = ((v - (w << sh)) >> (sh - 4)) * 10 // 16
        return str(w) + ('.%d' % d if w < 100 else '') + unit
    if v < 1024:
        return '%d %s' % (v, 'byte' if v == 1 else 'bytes')
    if v < 0x100000:
        return tenths(v, 10, ' KB')
    if v < 0x40000000:
        return tenths(v, 20, ' MB')
    return tenths(v, 30, ' GB')


def parse(console):
    t = open(console, 'rb').read().decode('latin-1').replace('\r', '\n')
    lines = re.findall(r'AB [^\n]*', t)
    if 'AB END' not in lines:
        fail('the session did not end ("AB END")')
    # each Refresh: the values (the last one wins); the numbers ("AB N ...")
    vals, nums, blocks = {}, {}, []
    for ln in lines:
        m = re.match(r'AB ([A-Za-z][^=]*)=(.*)$', ln)
        if m:
            vals[m.group(1)] = m.group(2)
            continue
        m = re.match(r'AB N (\w+) (\d+)$', ln)
        if m:
            nums[m.group(1)] = int(m.group(2))
            if m.group(1) == 'MHZ10':
                blocks.append(dict(nums))
    return lines, vals, blocks


def common(vals, blocks, rom, ram):
    k = open(rom, 'rb').read()[0x3F80]
    want = ('R%d' % k if k < 0x80 else 'R%d (a pre-release)' % (256 - k)) + ', version byte $%02X' % k
    if vals.get('KERNAL ROM') != want:
        fail('KERNAL ROM: %r, the ROM file\'s byte at $FF80: %r' % (vals.get('KERNAL ROM'), want))
    ok('KERNAL ROM: %s (the ROM file\'s $FF80)' % want)
    if not re.match(r'\d+\.\d+(\.\d+)?\S*, kernel \d+\.\d+, API level \d+, build \w+$', vals.get('Veranda', '')):
        fail('Veranda: %r' % vals.get('Veranda'))
    ok('Veranda: %s' % vals['Veranda'])
    inst = vals.get('Installed', '')
    if not (inst.startswith('not known (no /VERANDA/UPDATE.LST') or
            re.match(r'build [0-9A-Za-z._+-]+ of \d{4}-\d\d-\d\d \(Veranda Update\'s list on the card\)$', inst)):
        fail('Installed: %r' % inst)
    ok('Installed: %s' % inst)
    m = re.match(r'VERA (\d+)\.(\d+)\.(\d+), SMC (\d+)\.(\d+)\.(\d+)$', vals.get('VERA and SMC', ''))
    if not m:
        fail('VERA and SMC: %r' % vals.get('VERA and SMC'))
    emu = int(m.group(1)) >= 40
    if emu != vals.get('Machine', '').startswith('x16emu') or blocks[0]['EMU'] != int(emu):
        fail('Machine: %r with %r' % (vals.get('Machine'), vals.get('VERA and SMC')))
    ok('VERA and SMC: %s; the machine: %s' % (vals['VERA and SMC'], vals['Machine']))
    mhz = blocks[0]['MHZ10']
    if not 78 <= mhz <= 82:
        fail('the CPU: %d.%d MHz' % (mhz // 10, mhz % 10))
    ok('the CPU: %s' % vals['CPU'])
    for b in blocks:
        if b['TOTAL'] != ram // 8:
            fail('RAM: %d banks, the emulator has %d KB' % (b['TOTAL'], ram))
        if b['PROGS'] != {512: 43, 2048: 235}[ram]:
            fail('banks for programs: %d (DECISIONS V83, V165: 43 at 512 KB, 235 at 2 MB)' % b['PROGS'])
        if b['PROGS'] - b['FREE'] - b['ASIDE'] - b['MINE'] < 0:
            fail('the banks do not add up: %s' % b)
    if vals.get('RAM') != '%d KB: %d banks of 8 KB' % (ram, ram // 8):
        fail('RAM: %r' % vals.get('RAM'))
    ok('RAM: %s; the system %s; programs %d banks (DECISIONS V83)' % (vals['RAM'], vals['The system'].split(' (')[0],
                                                                       blocks[0]['PROGS']))
    now = time.time()
    try:
        t = time.mktime(time.strptime(vals.get('Date and time', ''), '%Y-%m-%d %H:%M:%S'))
    except ValueError:
        fail('the date and time: %r' % vals.get('Date and time'))
    if abs(now - t) > 600:
        fail('the date and time %s, the host\'s %s' % (vals['Date and time'], time.strftime('%Y-%m-%d %H:%M:%S')))
    ok('the clock: %s (the host\'s, -rtc)' % vals['Date and time'])
    m = re.match(r'(?:(\d+) h )?(\d+) min (\d+) s since the last reset', vals.get('Up', ''))
    if not m or int(m.group(2)) > 5:
        fail('up: %r' % vals.get('Up'))
    ok('up: %s' % vals['Up'].split(' since')[0])


def main():
    session, console, rom, ram = sys.argv[1:5]
    ram = int(ram)
    extra = sys.argv[5] if len(sys.argv) > 5 else None
    lines, vals, blocks = parse(console)
    common(vals, blocks, rom, ram)
    if session == 'host':
        if vals.get('Installed') != "build 1234abc of 2026-11-21 (Veranda Update's list on the card)":
            fail('Installed: %r (the card\'s VERANDA/UPDATE.LST says build 1234abc of 2026-11-21)' % vals.get('Installed'))
        b0, b1 = blocks[0], blocks[-1]
        if b0['FREE'] != b0['PROGS'] or b0['NASIDE'] != 0:
            fail('at the start: %s' % b0)
        task = [ln for ln in lines if ln.startswith('AB TASK ')]
        if not task or not task[-1].startswith('AB TASK AbHelper '):
            fail('the program aside: %s' % task)
        hb = int(task[-1].split()[-1])
        if b1['NASIDE'] != 1 or b1['ASIDE'] != hb or b1['FREE'] != b0['FREE'] - hb:
            fail('with AbHelper aside: %s (its banks %d)' % (b1, hb))
        if vals.get('Programs aside') != '%d banks: AbHelper (%d)' % (hb, hb):
            fail('Programs aside: %r' % vals.get('Programs aside'))
        ok('Alt+Tab: put aside and back; AbHelper aside with %d banks, listed, the free banks %d -> %d' % (
            hb, b0['FREE'], b1['FREE']))
        if 'AB ASIDE' not in lines or 'AB LIVE' not in lines:
            fail('no "AB ASIDE" or "AB LIVE"')
        if vals.get('Name') != 'Host folder' or vals.get('Card', '').find('none found') < 0:
            fail('the host folder, no UART: %r %r' % (vals.get('Name'), vals.get('Card')))
        if vals.get('Modem') != 'no card to ask':
            fail('Ask the modem with no card: %r' % vals.get('Modem'))
        ok('the host folder (no SD card), no UART: Ask the modem says "no card to ask"')
        import check_clip
        p = os.path.join(extra, 'VERANDA', '.SYSTEM', 'Text  Scrap.cvt')
        txt = check_clip.text(p)
        n = [int(ln.split()[-1]) for ln in lines if ln.startswith('AB COPIED ')]
        for want in (b'About this X16', b'KERNAL ROM: R', b'Free: 43 banks', b'Date and time: '):
            if want not in txt:
                fail('the Text Scrap has no %r' % want)
        ok('Copy: the Text Scrap holds the %d characters (the values, a line each)' % n[0])
    elif session == 'plain' and extra and extra.endswith('.img'):
        import vcard
        f = vcard.Fat32(extra)
        mbr = f.read(0, 512)
        part = struct.unpack_from('<I', mbr, 446 + 12)[0]
        fi = f.read(f.part + f.fsinfo * 512, 512)
        free = struct.unpack_from('<I', fi, 488)[0] * f.csize
        want = '%s FAT32, on a card of %s' % (ui_size(part * 512), ui_size(os.path.getsize(extra)))
        if vals.get('Name') != 'VERANDA' or vals.get('Size') != want or vals.get('Free') != ui_size(free):
            fail('the card: %r %r %r; the image: VERANDA, %r, %r' % (vals.get('Name'), vals.get('Size'),
                                                                   vals.get('Free'), want, ui_size(free)))
        ok('the SD card: VERANDA, %s, %s free (the image\'s partition, size and FSInfo)' % (want, ui_size(free)))
    elif session == 'plain':
        ok('%d KB: %d banks, %d for programs, %d free' % (ram, blocks[0]['TOTAL'], blocks[0]['PROGS'],
                                                          blocks[0]['FREE']))
    elif session == 'modem':
        if not vals.get('Card', '').startswith('a UART (16C550) at $9FE0'):
            fail('the network card: %r' % vals.get('Card'))
        if vals.get('Modem') != 'ZIMODEM ESP32 FIRMWARE V4.0.2 (x16emu)':
            fail('the modem: %r' % vals.get('Modem'))
        ok('the network card: %s; ATI: %s' % (vals['Card'], vals['Modem']))
        cmds = [ln.split(' ', 1)[1] for ln in open(extra).read().splitlines() if ln.startswith('@')]
        if not cmds or any(c not in ('AT', 'ATI') for c in cmds) or cmds[-1] != 'ATI':
            fail('the modem was sent %s' % cmds)
        ok('the modem was sent only %s (nothing that changes it: no ATB, ATZ or profile)' % ', '.join(cmds))
    else:
        fail('no such session ' + session)


if __name__ == '__main__':
    main()
