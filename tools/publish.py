#!/usr/bin/env python3
"""tools/publish.sh's helper (DECISIONS V139): the repository map, a
release's notes and BUILT FROM, the commit messages, the private list.

    publish.py repos [--map FILE]
        the map (tools/publish.repos), one repository a line, tab separated:
        repo tree key refs mode branch; refuses a port that is never published;
        leaves out the repositories of mode own (their maintainers push
        them: tools/publish.sh never does; DECISIONS V203)
    publish.py notes <tag> -o FILE
        the release's notes (the "- " points of the tag's message, before
        BUILT FROM) of this tree's tag veranda-<version>
    publish.py builtfrom <tag>
        "key hash" lines: the commits the release was built from
    publish.py strip <tree> --repo NAME [--private FILE]
        deletes what tools/publish.private names for NAME from an export
        folder; prints each path
    publish.py msg --version V --repo NAME --key KEY --source HASH
                   [--notes FILE] [--test] [--log FILE] -o FILE
        the commit message: "Veranda <version>" (a test: "Veranda test
        build <hash>"), the notes for veranda, the source's commit
        subjects since the last publish for the others (FILE: git log
        --format=%s output), cleaned as tools/relnotes.py cleans them
        (no V-numbers, no "asked for" asides), and the trailer
        "Veranda-Source: <key> <hash>", which the next publish reads

Run from the top of the tree. MIT licence (see LICENSE)."""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pubscan  # noqa: E402

MAP = os.path.join(HERE, 'publish.repos')
NEVER = ('geowrite', 'topdesk', 'commandersid', 'commander-sid')


def read_map(path=MAP):
    rows = []
    for l in open(path, encoding='utf-8'):
        if not l.strip() or l.lstrip().startswith('#'):
            continue
        f = [x.strip() for x in l.rstrip('\n').split(' | ')]
        if len(f) != 9:
            sys.exit('publish: %s: %d fields, not 9: %s' % (path, len(f), l.strip()))
        row = dict(zip(('repo', 'tree', 'key', 'refs', 'mode', 'branch', 'licence', 'build', 'output'), f))
        low = (row['repo'] + ' ' + row['tree'] + ' ' + row['key']).lower()
        for n in NEVER:
            if n in low:
                sys.exit('publish: %s names %s: never published (docs/PUBLISHING.md)' % (path, n))
        if row['mode'] not in ('export', 'history', 'own'):
            sys.exit('publish: %s: mode %s' % (row['repo'], row['mode']))
        rows.append(row)
    return rows


def git(*a):
    return subprocess.check_output(('git',) + a, universal_newlines=True)


def tag_body(tag):
    return git('tag', '-l', '--format=%(contents)', tag)


def clean(s):
    """a commit subject or a note made plain (relnotes.py's rules), cut to 200 characters"""
    import relnotes
    s = relnotes.plain(s).strip()
    return s if len(s) <= 200 else s[:197].rstrip() + '...'


def cmd_repos(a):
    for r in read_map(a.map):
        if r['mode'] == 'own':
            continue
        print('\t'.join((r['repo'], r['tree'], r['key'], r['refs'].replace(' ', ','), r['mode'], r['branch'])))


def cmd_notes(a):
    body = tag_body(a.tag)
    if not body.strip():
        sys.exit('publish: no tag %s (tools/release.sh makes it)' % a.tag)
    body = body.split('\nBUILT FROM')[0]
    import relnotes
    pts = relnotes.read_notes_text(body)
    pts = [p for p in pts if p.startswith('- ')] or ['- ' + p for p in pts]
    with open(a.o, 'w', encoding='utf-8') as f:
        f.write('\n'.join(pts) + '\n')


def cmd_builtfrom(a):
    import relnotes
    for k, h in relnotes.built_from(tag_body(a.tag)).items():
        print(k, h)


def cmd_strip(a):
    globs = pubscan.read_private(a.private, a.repo)
    for d, dirs, files in os.walk(a.tree, topdown=False):
        for fn in files:
            p = os.path.join(d, fn)
            rel = os.path.relpath(p, a.tree).replace(os.sep, '/')
            if pubscan.matches(rel, globs):
                os.remove(p)
                print(rel)
        if d != a.tree and not os.listdir(d):
            os.rmdir(d)


def cmd_msg(a):
    out = []
    if a.test:
        out.append('Veranda test build %s' % a.source[:7])
        out.append('')
        out.append('A test build for Veranda Update\'s Test channel, not a release.')
    else:
        out.append('Veranda %s' % a.version)
    pts = []
    if a.notes and a.repo == 'veranda':
        pts = [l.rstrip() for l in open(a.notes, encoding='utf-8') if l.startswith('- ')]
        pts = ['- ' + clean(p[2:]) for p in pts]
    elif a.log:
        seen = set()
        for l in open(a.log, encoding='utf-8'):
            c = clean(l)
            if c and c not in seen:
                seen.add(c)
                pts.append('- ' + c)
        if len(pts) > 30:
            pts = pts[:30] + ['- ... and %d more' % (len(pts) - 30)]
    if not a.test and a.repo != 'veranda':
        out += ['', 'Released with Veranda %s.' % a.version]
    if pts:
        out += ['', 'What changed:' if a.repo != 'veranda' else 'What is new:'] + pts
    out += ['', 'Veranda-Source: %s %s' % (a.key, a.source)]
    with open(a.o, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('repos')
    p.add_argument('--map', default=MAP)
    p.set_defaults(f=cmd_repos)
    p = sp.add_parser('notes')
    p.add_argument('tag')
    p.add_argument('-o', required=True)
    p.set_defaults(f=cmd_notes)
    p = sp.add_parser('builtfrom')
    p.add_argument('tag')
    p.set_defaults(f=cmd_builtfrom)
    p = sp.add_parser('strip')
    p.add_argument('tree')
    p.add_argument('--repo', required=True)
    p.add_argument('--private', default=pubscan.DEFAULT_PRIVATE)
    p.set_defaults(f=cmd_strip)
    p = sp.add_parser('msg')
    for k in ('--version', '--repo', '--key', '--source'):
        p.add_argument(k, required=True)
    p.add_argument('--notes')
    p.add_argument('--log')
    p.add_argument('--test', action='store_true')
    p.add_argument('-o', required=True)
    p.set_defaults(f=cmd_msg)
    a = ap.parse_args()
    a.f(a)


if __name__ == '__main__':
    main()
