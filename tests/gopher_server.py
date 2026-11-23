#!/usr/bin/env python3
"""Gate gopher (DECISIONS V109): a small Gopher server (RFC 1436) on
localhost for Veranda Gopher's test build, with Python's socket module
only.

usage: gopher_server.py <folder>   writes <folder>/ready (the port, then
                                   a port nothing listens on), <folder>/
                                   gopher.log (every selector) and the
                                   files it serves (<folder>/files/), so
                                   the gate can compare

The selectors:
  ""            the root menu: info lines (one empty, one of CP437 box
                characters), a submenu, a text, a long text, a search, a
                binary (9), a picture (g), a web link (h URL:), an error
                line (3), a menu on a port nothing listens on, a menu that
                stalls; Gopher's "." at the end
  /sub          a submenu (an item back to the root, with no host)
  /text.txt     a text: tabs, a paragraph longer than the window (wrapped
                at its spaces), a word longer than the window (cut), CR LF
                and LF line ends, CP437 characters; "." at the end
  /long.txt     80,000 bytes of numbered lines (more than the reader keeps)
  /search<TAB>q a menu: "You searched for: q"
  /big.bin      40,960 pseudo-random bytes, in pieces of 1,024
  /pic.gif      3,000 pseudo-random bytes
  /slow         a menu's first lines, then nothing for 120 s
  /many         a long menu (V110: the timings, a screenshot): a banner of
                CP437 box characters, info lines, every kind of item
  anything else "3" an error line
"""
import os
import random
import socket
import sys
import threading
import time

D = sys.argv[1]
LOCK = threading.Lock()
LOG = open(os.path.join(D, 'gopher.log'), 'w')
FILES = os.path.join(D, 'files')
os.makedirs(FILES, exist_ok=True)


def log(s):
    with LOCK:
        LOG.write(s + '\n')
        LOG.flush()


r = random.Random(109)
BIG = bytes(r.randrange(256) for _ in range(40960))
PIC = b'GIF89a' + bytes(r.randrange(256) for _ in range(2994))
open(os.path.join(FILES, 'big.bin'), 'wb').write(BIG)
open(os.path.join(FILES, 'pic.gif'), 'wb').write(PIC)

TEXT = (b'Veranda Gopher: a text file\r\n'
        b'\r\n'
        b'Tabs:\tone\ttwo\tthree\r\n'
        b'12345\t6\t7890\r\n'
        b'A paragraph that is longer than the window: the reader wraps it at its spaces, '
        b'so that no word is cut in two, and the next line starts with the next word.\r\n'
        b'Averyveryveryveryveryveryveryveryveryveryveryveryveryveryveryveryveryverylongwordwithnospaceatall.\n'
        b'LF only above; UTF-8 (V143): ' + '╔══╗ ░▒▓ ß, “quotes” – a dash…\r\nPolish: Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ'.encode() +
        b'\r\nLatin-1: caf\xe9 cr\xe8me \xe0 la fran\xe7aise\r\n'
        b'.\r\n')
open(os.path.join(FILES, 'text.txt'), 'wb').write(TEXT[:-3])
LONG = b''.join(b'Line %05d: the quick brown fox jumps over the lazy dog.\r\n' % i for i in range(1, 2000))
LONG = LONG[:80000]


def item(t, text, sel, host, port):
    return ('%s%s\t%s\t%s\t%d\r\n' % (t, text, sel, host, port)).encode('latin-1')


def info(text):
    return ('i%s\t\terror.host\t1\r\n' % text).encode('latin-1')


def root(port, closed):
    h = '127.0.0.1'
    return (info('Welcome to the gate\'s Gopher server.') +
            info('') +
            item('1', 'A submenu', '/sub', h, port) +
            item('0', 'A text file', '/text.txt', h, port) +
            item('0', 'A long text', '/long.txt', h, port) +
            item('7', 'Search the gate', '/search', h, port) +
            item('9', 'A binary file', '/big.bin', h, port) +
            item('g', 'A picture', '/pic.gif', h, port) +
            item('h', 'The web', 'URL:http://example.com/a/page.html', h, port) +
            item('3', 'An error line: this item is gone', '', 'error.host', 1) +
            item('1', 'A closed port', '/', h, closed) +
            item('1', 'A menu that stalls', '/slow', h, port) +
            ('i╔══╗ box lines ░▒▓\terror.host\t1\r\n'
             'iPolish (V143): Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ\terror.host\t1\r\n').encode() +
            b'.\r\n')


def many(port):
    h = '127.0.0.1'
    def box(t):
        return ('i║' + t.ljust(40) + '║\t\terror.host\t1\r\n').encode()     # (V143: UTF-8)
    out = (('i╔' + '═' * 40 + '╗\t\terror.host\t1\r\n').encode() + box('  Veranda Gopher: a long menu') +
           box('  ░▒▓█ every kind of item █▓▒░') +
           ('i╚' + '═' * 40 + '╝\t\terror.host\t1\r\n').encode() + info(''))
    kinds = [('1', 'A menu'), ('0', 'A text'), ('7', 'A search'), ('9', 'A binary'), ('g', 'A GIF picture'),
             ('I', 'An image'), ('s', 'A sound'), ('5', 'An archive'), ('d', 'A document'), ('h', 'A web page'),
             ('8', 'A telnet session'), ('2', 'A CSO phone book'), ('3', 'An error')]
    for n in range(4):
        out += info('Part %d: some information about the items below, as menus often have.' % (n + 1))
        for t, name in kinds:
            sel = 'URL:http://example.com/' if t == 'h' else '/x/%s%d' % (t, n)
            out += item(t, '%s, number %d' % (name, n + 1), sel, h, port)
        out += info('')
    return out + b'.\r\n'


def serve(c, port, closed):
    try:
        req = b''
        c.settimeout(20)
        while b'\n' not in req:
            k = c.recv(1024)
            if not k:
                return
            req += k
        sel = req.split(b'\n')[0].rstrip(b'\r').decode('latin-1')
        log('SEL ' + sel.replace('\t', '<TAB>'))
        q = None
        if '\t' in sel:
            sel, q = sel.split('\t', 1)
        if sel == '':
            c.sendall(root(port, closed))
        elif sel == '/sub':
            c.sendall(info('The submenu') + item('0', 'The text again', '/text.txt', '127.0.0.1', port) +
                      b'1Back to the top\t\t\t\r\n' + b'.\r\n')
        elif sel == '/text.txt':
            c.sendall(TEXT)
        elif sel == '/long.txt':
            for i in range(0, len(LONG), 4096):
                c.sendall(LONG[i:i + 4096])
        elif sel == '/search':
            c.sendall(info('You searched for: %s' % q) + item('0', 'A result', '/text.txt', '127.0.0.1', port) + b'.\r\n')
        elif sel == '/big.bin':
            for i in range(0, len(BIG), 1024):
                c.sendall(BIG[i:i + 1024])
                time.sleep(0.01)
        elif sel == '/pic.gif':
            c.sendall(PIC)
        elif sel == '/many':
            open(os.path.join(D, 'many.txt'), 'wb').write(many(port))
            c.sendall(many(port))
        elif sel == '/slow':
            c.sendall(info('The first lines of a menu that stalls') + info('(the rest never comes)'))
            time.sleep(120)
        else:
            c.sendall(item('3', 'No such selector: ' + sel, '', 'error.host', 1) + b'.\r\n')
    except OSError as e:
        log('ERR ' + str(e))
    finally:
        try:
            c.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        c.close()
        log('CLOSED')


def main():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 0))
    s.listen(8)
    port = s.getsockname()[1]
    t = socket.socket()
    t.bind(('127.0.0.1', 0))
    closed = t.getsockname()[1]
    t.close()                           # (a port nothing listens on)
    open(os.path.join(D, 'ready.tmp'), 'w').write('%d %d\n' % (port, closed))
    os.rename(os.path.join(D, 'ready.tmp'), os.path.join(D, 'ready'))
    while True:
        c, _ = s.accept()
        threading.Thread(target=serve, args=(c, port, closed), daemon=True).start()


main()
