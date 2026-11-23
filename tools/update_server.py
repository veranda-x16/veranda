#!/usr/bin/env python3
"""Veranda Update's PC source (DECISIONS V130): your own Veranda builds,
served to your X16 over your home network.

Copy this file to a PC on the same network as the X16, next to a Veranda
package folder (the folder tools/mkdist.sh makes: VERANDA/, PC/,
DOCUMENTS/; VERANDA/UPDATE.LST is its manifest), and run (Python 3,
nothing to install):

    python3 update_server.py /path/to/the/package

It listens on port 8644 (--port) and prints the PC's address. In Veranda
Update choose Source..., "a PC on my network", and type that address
(e.g. 192.168.1.20:8644). Check then compares the card with the package
and Update brings over what changed.

What it serves (plain HTTP/1.1, GET only, Content-Length, Connection:
close):
    /UPDATE.LST      the package's manifest (VERANDA/UPDATE.LST)
    /<crc32>.bin     a file of the package by the asset name its manifest
                     line gives (the file is read again and its CRC-32
                     checked against the manifest on every request)
Anything else: 404. Only the files the manifest names can be fetched.

This is for your own builds, ports and all: only private addresses may
connect (loopback, 10/8, 172.16/12, 192.168/16; IPv6 loopback,
unique-local, link-local), and the files cross your network unencrypted.
Never forward its port to the Internet.

MIT licence, Copyright (c) 2026 Marcin Spoczynski."""
import argparse
import http.server
import ipaddress
import os
import socket
import sys
import time
import zlib

DEFAULT_PORT = 8644
FORMAT = 'VERANDA-UPDATE 1'


def log(msg):
    sys.stderr.write('%s  %s\n' % (time.strftime('%H:%M:%S'), msg))
    sys.stderr.flush()


_PRIVATE4 = [ipaddress.ip_network(n) for n in ('127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]
_PRIVATE6 = [ipaddress.ip_network(n) for n in ('::1/128', 'fc00::/7', 'fe80::/10')]


def allowed_client(addr):
    """the X16 must be on this PC's own network"""
    try:
        ip = ipaddress.ip_address(addr.split('%')[0])
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    nets = _PRIVATE4 if ip.version == 4 else _PRIVATE6
    return any(ip in n for n in nets)


def read_manifest(pkg):
    """(the manifest's bytes, {asset: (path, size, crc)})"""
    path = os.path.join(pkg, 'VERANDA', 'UPDATE.LST')
    with open(path, 'rb') as f:
        raw = f.read()
    text = raw.decode('latin-1')
    lines = text.split('\n')
    if lines[0].strip() != FORMAT:
        raise ValueError('%s is not a %s manifest' % (path, FORMAT))
    assets, ended = {}, False
    for l in lines[1:]:
        l = l.rstrip('\r')
        if l.startswith('file '):
            f = l[5:].split(' ', 5)
            assets.setdefault(f[4], (f[5], int(f[0]), int(f[1], 16)))
        elif l.startswith('end '):
            ended = True
    if not ended:
        raise ValueError('%s has no end line (cut short?)' % path)
    return raw, assets


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'VerandaUpdateServer/1.0'

    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype='application/octet-stream'):
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self):
        S = self.server
        name = self.path.split('?', 1)[0].lstrip('/')
        try:
            raw, assets = read_manifest(S.pkg)
        except (OSError, ValueError) as e:
            log('%s  %s: no manifest: %s' % (self.client_address[0], self.path, e))
            self.send(500, b'no manifest\n', 'text/plain')
            return
        if name == 'UPDATE.LST':
            log('%s  UPDATE.LST (%d bytes)' % (self.client_address[0], len(raw)))
            self.send(200, raw, 'text/plain')
            return
        if name not in assets:
            log('%s  %s: not in the manifest (404)' % (self.client_address[0], self.path[:80]))
            self.send(404, b'not found\n', 'text/plain')
            return
        path, size, crc = assets[name]
        full = os.path.join(S.pkg, *path.split('/'))
        try:
            with open(full, 'rb') as f:
                data = f.read()
        except OSError:
            data = None
        if data is None or len(data) != size or (zlib.crc32(data) & 0xFFFFFFFF) != crc:
            log('%s  %s (%s): changed since the manifest was made (409)' % (self.client_address[0], name, path))
            self.send(409, b'the package changed: make its manifest again\n', 'text/plain')
            return
        log('%s  %s (%s, %d bytes)' % (self.client_address[0], name, path, size))
        self.send(200, data)

    def do_HEAD(self):
        self.send(405, b'')

    do_POST = do_PUT = do_DELETE = do_HEAD


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def verify_request(self, request, client_address):
        if allowed_client(client_address[0]):
            return True
        log('%s  refused: not a private address' % client_address[0])
        return False


def lan_address():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('10.255.255.255', 1))       # (no packet is sent)
        a = s.getsockname()[0]
        s.close()
        return a
    except OSError:
        return '127.0.0.1'


def main():
    ap = argparse.ArgumentParser(description='Veranda Update\'s PC source: a package served to your X16.')
    ap.add_argument('pkg', help='the package folder (VERANDA/UPDATE.LST in it)')
    ap.add_argument('--port', type=int, default=DEFAULT_PORT)
    ap.add_argument('--bind', default='0.0.0.0')
    ap.add_argument('--ready', help=argparse.SUPPRESS)  # (gate update: the port written here once listening)
    a = ap.parse_args()
    try:
        _, assets = read_manifest(a.pkg)
    except (OSError, ValueError) as e:
        sys.exit('update_server: %s' % e)
    s = Server((a.bind, a.port), Handler)
    s.pkg = a.pkg
    port = s.server_address[1]
    log('serving %s (%d files) on port %d: in Veranda Update, Source..., a PC on my network, %s:%d'
        % (a.pkg, len(assets), port, lan_address(), port))
    log('only private addresses may connect; plain HTTP on your network')
    if a.ready:
        with open(a.ready, 'w') as f:
            f.write('%d\n' % port)
    try:
        s.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
