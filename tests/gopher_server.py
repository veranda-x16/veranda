#!/usr/bin/env python3
"""Gate gopher (DECISIONS V109): a small Gopher server (RFC 1436) on
localhost for Veranda Gopher's test build, with Python's socket module
only.

usage: gopher_server.py <folder>   writes <folder>/ready (the port, then
                                   a port nothing listens on), <folder>/
                                   gopher.log (every selector) and the
                                   files it serves (<folder>/files/; V230:
                                   the quux pages as sent, <folder>/quux/),
                                   so the gate can compare

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
  /quux, /Archives..., "/About This Server.txt"
                (V230) gopher.quux.org's shapes (quux() below): its root,
                Archives, "Mailing Lists", Usenet Archives from 1981 (121
                items), a group of 75 articles and one of 995 (113 KB), an
                article, texts; no "." line on any of them
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


# (V230) gopher.quux.org's shapes (its "Usenet Archives from 1981" and the
# pages on the way): menus with CR LF, a Gopher+ "+" fifth field on most
# items, info lines "fake (NULL) 0", selectors up to 70 characters, some
# with spaces, a directory of 121 items; texts with LF only, one that
# starts with an empty line and has Latin-1; and no "." line at the end
# of any of them: the server sends the page and closes
GROUPS = ('FA.apollo FA.arms-d FA.arpa-bboard FA.digest-p FA.dungeon FA.editor-p FA.energy FA.human-nets '
          'FA.info-cpm FA.info-micro FA.info-terms FA.info-vax FA.poli-sci FA.printers FA.railroad FA.sf-lovers '
          'FA.space FA.tcp-ip FA.telecom FA.test FA.unix-cpm FA.unix-wizards FA.works NET.ALL NET.adm.site NET.ao '
          'NET.apl.lang NET.applic NET.arpa-uucp NET.auto NET.aviation NET.blfp NET.bugs NET.bugs.2bsd NET.bugs.4bsd '
          'NET.bugs.uucp NET.bugs.v7 NET.chess NET.cms NET.columbia NET.cooks NET.crap NET.cse NET.csfrp NET.cycle '
          'NET.db NET.dbms NET.dcom NET.draw NET.eunice NET.flame NET.followup NET.games NET.gdead NET.general '
          'NET.groups.control NET.ham-radio NET.info-cpm NET.info-micro NET.info-terms NET.jobs NET.jokes NET.junk '
          'NET.lan NET.lang.apl NET.lisp NET.lsi NET.man NET.map NET.math NET.mc NET.micro NET.misc NET.motorcycles '
          'NET.movies NET.msg.ctl NET.music NET.news NET.news.b NET.news.directory NET.news.groups NET.news.map '
          'NET.news.newsite NET.oa NET.periphs NET.railroad NET.rec.birds NET.rec.bridge NET.rec.photo NET.rec.scuba '
          'NET.rec.ski NET.records NET.rumor NET.scuba NET.sf-lovers NET.skum NET.sources NET.space '
          'NET.sport.baseball NET.sport.football NET.sport.hockey NET.suicide NET.swl NET.taxes NET.test NET.tools '
          'NET.travel NET.trivia NET.ucds NET.unix NET.unix-wizards NET.usenix NET.video NET.vwrabbit NET.wanted '
          'NET.wines NET.works NET.xbsd').split()
SUBJECTS = ['  Digest for workstation discussion', '  The same is the same', ' Apollo Users Workshop (6/22 - 6/23)',
            ' Execution speed of various machines', 'Are Windows Necessary?', 'Most recent IBM system\'s journal: '
            'vol 20, # 2 1981', 'Preliminary results from the personal workstations survey',
            'The Impact of Xerox on Lanugage Design -- ... on Mesa', 'Re: PERQ\'s and UNIX', 'Star/Mesa']
ART = '/Archives/usenet-a-news/FA.apollo/81.06.%02d_ucbvax.%04d_fa.apollo.txt'


def qitem(t, text, sel, port, plus=True):
    return ('%s%s\t%s\t127.0.0.1\t%d%s\r\n' % (t, text, sel, port, '\t+' if plus else '')).encode('latin-1')


def qinfo(text):
    return ('i%s\tfake\t(NULL)\t0\r\n' % text).encode('latin-1')


def quux(sel, port):
    """the page for sel (bytes), None: not one of these"""
    if sel == '/quux':                  # (its root)
        return (qinfo('Welcome to gopher at quux.org!') + qinfo('') +
                qinfo('This server has a lot of information of historic interest,') + qinfo('') +
                qitem('0', 'About This Server', '/About This Server.txt', port) +
                qitem('1', 'Archives', '/Archives', port) + qitem('1', 'Books', '/Books', port) +
                qitem('1', 'Humor and Fun', '/Humor and Fun', port) +
                qitem('1', 'Index to Quux.Org', '/Archives/index', port, False))
    if sel == '/Archives':
        return (qitem('1', 'Mailing Lists', '/Archives/Mailing Lists', port) +
                qitem('0', 'Project Gutenberg Online Books', '/Archives/gutenberg', port, False) +
                qitem('1', 'Usenet Archives from 1981', '/Archives/usenet-a-news', port) +
                qitem('1', 'Wiretap Electronic Documents', '/Archives/mirrors/wiretap.area.com', port, False))
    if sel == '/Archives/Mailing Lists':
        return (qitem('1', '9-11peace', '/Archives/Mailing Lists/9-11peace', port) +
                qitem('1', 'gopher', '/Archives/Mailing Lists/gopher', port))
    if sel == '/Archives/usenet-a-news':
        return (qitem('0', 'Introduction', '/Archives/usenet-a-news/intro.txt', port) +
                qitem('0', 'Copyright and History', '/Archives/usenet-a-news/copyright.txt', port) +
                b''.join(qitem('1', g, '/Archives/usenet-a-news/' + g, port) for g in GROUPS) +
                qitem('1', 'utils', '/Archives/usenet-a-news/utils', port))
    if sel == '/Archives/usenet-a-news/FA.apollo':
        return b''.join(qitem('0', SUBJECTS[i % len(SUBJECTS)], ART % (11 + i % 7, 1600 + i), port) for i in range(75))
    if sel == ART % (11, 1600):
        return (b'Aucbvax.1600\nfa.apollo\nutzoo!duke!ucbvax!someone@Somewhere\nFri Jun 12 14:58:56 1981\n'
                b'  Digest for workstation discussion\n\n'
                b'I assumed that these discussions WOULD be a digest.  PLEASE make\n'
                b'it a digest: forty or more messages a day are hard to follow.\n\n\n\n'
                b'-----------------------------------------------------------------\n'
                b' The Usenet Oldnews Archive: Compilation Copyright (C) 1981, 1996 \n'
                b' Bruce Jones, Henry Spencer, David Wiseman.\n\n')
    if sel == '/Archives/usenet-a-news/copyright.txt':
        return (b'\nUsenet Oldnews Copyright \xa9 Notice\n\n    This archive of Usenet News articles represents the\n'
                b'    resources and energy of many people.  It is under compilation copyright \xa9\n'
                b'    by its compilers.\n')
    if sel == '/Archives/usenet-a-news/NET.general':     # (995 articles, 117 KB: more than the reader keeps)
        subj = [' Source Code Control System Questionaire', 'Re: Copyrights', 'net.general', 'UNIX on the VAX',
                'Defy rabbit riders!']          # (its subjects' length, some 20 characters on the mean)
        return b''.join(qitem('0', subj[i % 5], '/Archives/usenet-a-news/NET.general/8%d.%02d.%02d_site%d.%d_'
                              'net.general%s.txt' % (1 + i % 2, 1 + i % 12, 1 + i % 28, i % 9, 100 + i,
                                                     ',fa.unix-wizards' if i % 9 == 0 else ''), port)
                        for i in range(995))
    if sel.startswith('/Archives/usenet-a-news/NET.general/'):
        return (b'Aazure.122\nnet.general,fa.unix-wizards\nucbvax!azure!someone\nMon Jul 27 10:00:00 1981\n'
                b' Source Code Control System Questionaire\n\nWho uses SCCS on their systems?\n\n\n')
    if sel == '/About This Server.txt':
        return b''.join(b'Line %02d of a text about the server, with LF line ends and no "." line at the end.\n' % i
                        for i in range(1, 50))
    return None


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
        qx = quux(sel, port)
        if qx is not None:
            os.makedirs(os.path.join(D, 'quux'), exist_ok=True)
            open(os.path.join(D, 'quux', sel.replace('/', '_')), 'wb').write(qx)
            c.sendall(qx)
        elif sel == '':
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
