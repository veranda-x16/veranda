#!/usr/bin/env python3
"""gate da: checks the native desk accessories' sessions (tools/gate_da.sh,
tests/da_script.py) on the host: the console, the files they wrote, the
dumps (-dump RV: RAM $0000-$9FFF, then VRAM and VERA's registers).

usage: check_da.py dex <run> <sysdir> online|dial
       check_da.py cal <run> <sysdir>
       check_da.py alarmshot <dump.bin>
       check_da.py prefs1 <run> <sysdir>
       check_da.py reboot <run>
       check_da.py prefs2 <run> <sysdir>
<sysdir>: the system folder in the run folder ("VERANDA" or "." for the root).
With VERANDA the layout of DECISIONS V71: the system's files in
VERANDA/.SYSTEM, the accessories, Term and TopDesk in VERANDA/APPS,
DESKTOP.cvt in VERANDA.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mksounds  # noqa: E402

VDUMP = 132878
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def console(run):
    c = open(os.path.join(run, 'console.txt'), 'rb').read().decode('latin-1')
    return re.sub(r'\\X[0-9A-F]{2}', '', c).replace('\r', '')


def in_order(con, want):
    p = 0
    for m in want:
        p = con.find(m, p)
        if p < 0:
            return False, m
        p += len(m)
    return True, ''


def cvt(path):
    """a CVT file: (entry, info block, data or records)"""
    d = open(path, 'rb').read()
    ent, info = d[:30], d[254:508]
    if ent[21] == 0:
        return ent, info, d[508:]
    tab = d[508:762]
    recs, off = [], 762
    for i in range(0, 254, 2):
        b, last = tab[i], tab[i + 1]
        if b == 0 and last == 0:
            break
        if b == 0:
            recs.append(None)
            continue
        n = (b - 1) * 254 + last - 1
        recs.append(d[off:off + n])
        off += b * 254
    return ent, info, recs


def name_of(ent):
    return bytes(ent[3:19]).split(b'\xa0')[0].decode('latin-1')


def class_of(info):
    return bytes(info[75:95]).split(b'\0')[0].decode('latin-1')


def screens(run):
    pre, post = os.path.join(run, 'PRE.RAW'), os.path.join(run, 'POST.RAW')
    if os.path.exists(post):
        check(open(pre, 'rb').read() == open(post, 'rb').read(),
              'both of Paint\'s screens when GetFile returned equal those when the accessory opened (76,800 bytes)')


def vram(path):
    d = open(path, 'rb').read()
    return d, d[len(d) - VDUMP:]


def pal(v, i):
    # vram2png's layout: VRAM (128 KB), the composer's registers, the palette
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
    import vram2png
    p = v[vram2png.VRAM + vram2png.COMPOSER:]
    return p[2 * i] | p[2 * i + 1] << 8


# ---------------------------------------------------------------- Dex
CARDS = [('Alice Example', 'bbs.test:23', 'alice@example.org', '1 Main Street, Springfield', 'Sysop, "the" BBS'),
         ('Bob Builder', '555-0101', 'bob@example.org', '', ''),
         ('Carol Smith', '555-0199', '', 'Elm Road 7', 'Birthday, 3 May')]


def csv_line(f):
    out = []
    for s in f:
        if any(c in s for c in ',"\r\n'):
            s = '"' + s.replace('"', '""') + '"'
        out.append(s)
    return ','.join(out) + '\r\n'


def data_dir(run, sd):
    return os.path.join(run, sd, '.SYSTEM') if sd != '.' else run


def apps_dir(run, sd):
    return os.path.join(run, sd, 'APPS') if sd != '.' else run


def dex(run, sd, dial):
    con = console(run)
    want = ['PAINT RUNNING', 'DEX RUNNING 0', 'DEX SAVED 1', 'DEX SAVED 2', 'DEX SAVED 3', 'DEX FIND bo 1',
            'DEX FIND  3', 'DEX EXPORTED 3', 'DEX COPIED', 'DEX CONNECT bbs.test:23', 'TERM RUNNING',
            'TERM DOC', 'bbs.test:23', 'TERM END']
    ok, miss = in_order(con, want)
    check(ok, 'the console in order: three cards saved, "bo" finds one, export, copy, connect, Term with the '
          'document' + (' (missing: %s)' % miss if miss else ''))
    s = data_dir(run, sd)
    ent, info, recs = cvt(os.path.join(s, 'Dex Cards.cvt'))
    got = [tuple(r.split(b'\0')[:5]) for r in recs]
    exp = [tuple(x.encode() for x in c) for c in CARDS]
    check(name_of(ent) == 'Dex Cards' and ent[22] == 7 and ent[21] == 1 and class_of(info) == 'Dex Cards V1.0',
          'Dex Cards.cvt in the system folder: a record file (APPL_DATA), class "Dex Cards V1.0"')
    check(got == exp, 'its records: the three cards in name order, five fields each (%d records)' % len(recs))
    csv = open(os.path.join(run, 'DEX.CSV'), 'rb').read().decode('latin-1')
    want_csv = csv_line(['Name', 'Phone, host', 'E-mail', 'Address', 'Note']) + ''.join(csv_line(c) for c in CARDS)
    check(csv == want_csv, 'DEX.CSV in the application\'s folder: RFC 4180, a header and three lines, CR LF, '
          'quotes where a field has a comma or a quote (%d bytes)' % len(csv))
    # Commander Calc's reader (src/import/csv.c) by the same rules: fields back
    rows, field, row, q, i = [], '', [], False, 0
    while i < len(csv):
        c = csv[i]
        if q:
            if c == '"' and csv[i + 1:i + 2] == '"':
                field += '"'
                i += 1
            elif c == '"':
                q = False
            else:
                field += c
        elif c == '"':
            q = True
        elif c == ',':
            row.append(field)
            field = ''
        elif c == '\r':
            pass
        elif c == '\n':
            row.append(field)
            rows.append(tuple(row))
            row, field = [], ''
        else:
            field += c
        i += 1
    check(rows[1:] == CARDS, 'read back as Veranda Calc reads CSV: the cards\' fields')
    ent, info, data = cvt(os.path.join(s, 'Text  Scrap.cvt'))
    n = data[0] | data[1] << 8
    text = data[2:2 + n]
    if text[:1] == b'\x17':
        text = text[4:]
    check(text == b'Alice Example\rbbs.test:23\ralice@example.org\r1 Main Street, Springfield\rSysop, "the" BBS\r',
          'Copy: the Text Scrap holds Alice\'s card, a line a field')
    tel = open(os.path.join(apps_dir(run, sd), 'DEX.TEL'), 'rb').read()
    check(tel == b'Alice Example|bbs.test:23\r', 'Connect: DEX.TEL next to Veranda Term: "Alice Example|bbs.test:23"')
    m = re.search(r'TERM DOC\n(.*)\n', con)
    check(bool(m) and m.group(1) == 'bbs.test:23', 'Veranda Term started with the document (ST_LD_DATA) dials '
          'its host')
    if dial == 'online':
        m = re.search(r'TERM TN ([0-9]+)', con)
        check('TERM RUNNING\n' in con and bool(m) and int(m.group(1)) > 0,
              'through the emulator\'s UART Term dialled the fake BBS and got online: Telnet negotiated '
              '(%s option bytes)' % (m.group(1) if m else '?'))
    else:
        check('TERM END' in con, 'Term dialled (no UART: the dial\'s start) and its test ended')


# ---------------------------------------------------------------- the Calendar
def cal(run, sd):
    con = console(run)
    want = ['DADESK RUNNING', 'CAL RUNNING 0', 'CAL SAVED 1', 'CAL ALARMS 1', 'CAL CLOSED', 'DADESK BACK',
            'ALARM 12:00 Dentist']
    ok, miss = in_order(con, want)
    check(ok, 'the console in order: the appointment saved, one alarm armed, the Calendar closed, then in the '
          'test program the kernel\'s alarm' + (' (missing: %s)' % miss if miss else ''))
    # (V91) the program's interrupt counter, in zero page and in RAM: equal
    # when GetFile returns (its routine stopped before the program was
    # packed), and both 30 on later
    cnt = [(int(a, 16), int(b, 16)) for a, b in re.findall(r'DADESK COUNT ([0-9A-F]{4}) ([0-9A-F]{4})', con)]
    check(len(cnt) == 2 and cnt[0][0] == cnt[0][1] >= 20 and cnt[1][0] == cnt[1][1] >= cnt[0][0] + 30,
          'the program\'s interrupt counter in zero page equals its copy in RAM after the accessory, and counts on '
          '(%s)' % ', '.join('%d %d' % c for c in cnt))
    s = data_dir(run, sd)
    ent, info, recs = cvt(os.path.join(s, 'Appointments.cvt'))
    check(class_of(info) == 'Appointments V1.0' and len(recs) == 1
          and recs[0] == bytes([26, 11, 16, 12, 0, 1]) + b'Dentist'.ljust(26, b'\0'),
          'Appointments.cvt: record 0, one entry: 2026-11-16 12:00, the alarm, "Dentist"')
    ent, info, data = cvt(os.path.join(s, 'Veranda Alarms.cvt'))
    check(name_of(ent) == 'Veranda Alarms' and ent[22] == 4 and len(data) == 256
          and data[:32] == bytes([26, 11, 16, 12, 0, 1]) + b'Dentist'.ljust(26, b'\0') and not any(data[32:]),
          'Veranda Alarms.cvt (SYSTEM, 256 bytes): the alarm armed, the rest empty')
    # the alarm's sound (V69: SND_ALARM, tools/mksounds.py), as the test
    # program's intFirstVector saw PSG voice 15 (its frame counter: 8 bits)
    tail = con[con.find('ALARM 12:00'):]
    psg = re.findall(r'PSG 15 ([0-9A-F]{4}) ([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{2})', tail)
    seq = [(int(a, 16), int(b, 16), int(c, 16)) for a, b, c, _ in psg]
    frames = [int(x[3], 16) for x in psg]
    while seq and not seq[0][1] & 63:           # (the silence before it)
        seq.pop(0)
        frames.pop(0)
    want = mksounds.trace(mksounds.ALARM, 15)
    exp = [r for _, r in want]
    gaps = [(b - a) & 255 for a, b in zip(frames, frames[1:])]
    check(seq == exp and gaps == [b[0] - a[0] for a, b in zip(want, want[1:])],
          'the alarm with the box: PSG voice 15 as SND_ALARM\'s table (%d changes: three rings of an E6-C6 '
          'trill, then silent)' % len(seq))
    d, v = vram(os.path.join(run, 'dump.bin'))
    check(d[0x54F:0x554] >= bytes([26, 11, 16, 12, 0]), 'Veranda\'s clock past the alarm at the end: %d-%d-%d '
          '%d:%02d:%02d' % tuple(d[0x54F:0x555]))


def alarmshot(path):
    """the box (the default dialog box, 224-415 x 192-287) over the test
    program's backdrop: its frame, its shadow"""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
    import vram2png
    v = vram2png.section(path)

    def px(x, y):
        return v[y * 80 + x // 8] >> (7 - x % 8) & 1
    top = all(px(x, 192) for x in range(224, 416))
    left = all(px(224, y) for y in range(192, 288))
    inside = sum(px(x, y) for x in range(232, 400) for y in range(230, 236))
    shadow = all(px(x, 290) for x in range(240, 420))
    check(top and left and shadow and inside < 50, 'the alarm\'s box over the test program: its frame at '
          '224-415 x 192-287, the shadow, white inside')


# ---------------------------------------------------------------- Preferences
P1 = bytes([0xFD, 0x0F, 0x26, 0x00, 120, 0, 0x81, 0xFF, 0, 1, 3, 14, 5, 0x85, 0x80, 0])


def prefs1(run, sd):
    con = console(run)
    want = ['PAINT RUNNING', 'PREFS RUNNING', 'PREFS DESKTOP TOPDESK',
            'PREFS SAVED ' + ' '.join(str(b) for b in P1), 'PREFS CLOSED', 'PAINT DESK BACK']
    ok, miss = in_order(con, want)
    check(ok, 'the console in order: the desktop copied, the settings saved, closed, Paint back'
          + (' (missing: %s)' % miss if miss else ''))
    s = data_dir(run, sd)
    ent, info, data = cvt(os.path.join(s, 'Veranda Prefs.cvt'))
    check(name_of(ent) == 'Veranda Prefs' and ent[22] == 4 and class_of(info) == 'Veranda Prefs V1.0'
          and data == P1, 'Veranda Prefs.cvt: SYSTEM, its data the settings block: paper $0FFD, ink $0026, '
          'blanking 120 s, the beep off and the pointer x2 ($81), no mode, UTC, TopDesk, the theme Sunroom '
          '(3, 14, 5, $85, Look 2\'s $80: none was saved before; V74, V132)')
    check(open(os.path.join(run, sd, 'DESKTOP.cvt'), 'rb').read()
          == open(os.path.join(apps_dir(run, sd), 'TopDesk.cvt'), 'rb').read(),
          'DESKTOP.cvt is a copy of TopDesk.cvt (DECISIONS V46)')
    screens(run)
    d, v = vram(os.path.join(run, 'dump.bin'))
    check(pal(v, 0) == 0x0FFF and pal(v, 1) == 0x0223, 'Paint\'s own colours back after the accessory (palette '
          'entries 0 and 1 white and slate (V74); the preview went with it)')
    check(d[0x55A] | d[0x55B] << 8 == 120, 'blankDelay 120 at once (SysPrefs PREFS_SET)')


def reboot(run):
    con = console(run)
    m = re.search(r'DADESK PREFS ((?:[0-9A-F]{2} ?){16})', con)
    got = bytes(int(x, 16) for x in m.group(1).split()) if m else b''
    check(got == P1, 'after a new start the test desktop (DESKTOP.cvt) runs, and the kernel holds the settings '
          'read from Veranda Prefs (SysPrefs PREFS_GET)')
    m = re.search(r'DADESK PALETTE ([0-9A-F]{4}) ([0-9A-F]{4}) BLANK ([0-9A-F]{4})', con)
    check(bool(m) and m.groups() == ('0FFD', '0026', '0078'), 'palette entries 0 and 1 the saved paper and ink '
          '(AppReset\'s DefColors), blankDelay 120 (the program\'s view)')
    d, v = vram(os.path.join(run, 'dump.bin'))
    check(pal(v, 0) == 0x0FFD and pal(v, 1) == 0x0026 and d[0x55A] | d[0x55B] << 8 == 120,
          'the dump: palette entries 0 and 1 $0FFD and $0026, blankDelay ($055A) 120')


def prefs2(run, sd):
    con = console(run)
    ok, miss = in_order(con, ['PREFS RUNNING', 'PREFS DESKTOP SHELL', 'PREFS SAVED', 'PREFS CLOSED',
                              'PAINT DESK BACK'])
    check(ok, 'the console in order: the desktop back to the shell, saved, closed, Paint back'
          + (' (missing: %s)' % miss if miss else ''))
    check(not os.path.exists(os.path.join(run, sd, 'DESKTOP.cvt')), 'DESKTOP.cvt deleted: the shell is the desktop again')
    ent, info, data = cvt(os.path.join(data_dir(run, sd), 'Veranda Prefs.cvt'))
    check(data[9] == 0 and data[:9] == P1[:9], 'Veranda Prefs.cvt: the desktop byte 0, the rest as before')
    screens(run)


def main():
    a = sys.argv[1:]
    {'dex': lambda: dex(a[1], a[2], a[3]), 'cal': lambda: cal(a[1], a[2]), 'alarmshot': lambda: alarmshot(a[1]),
     'prefs1': lambda: prefs1(a[1], a[2]), 'reboot': lambda: reboot(a[1]),
     'prefs2': lambda: prefs2(a[1], a[2])}[a[0]]()
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
