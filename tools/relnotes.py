#!/usr/bin/env python3
"""A release's texts (docs/RELEASING.md), for tools/release.sh.

    relnotes.py notes --since REV [--version V] [-o FILE]
        "what's new" since REV: one bullet a line, in plain words, from the
        DECISIONS rows added since REV (their bold titles) and the commit
        subjects since REV that no such row covers
    relnotes.py readme PKG --version V --since REV --notes FILE
                       [--checklist FILE] [--prev-refs FILE] [--tilehw]
        appends to PKG/VERANDA/README.txt: NEW IN THIS BUILD, the tile
        test (--tilehw), the hardware checklist (tools/checklist.txt, the
        sections whose sources changed since REV marked NEW, first); writes
        PKG/VERANDA/CHANGES.txt (this version, the versions before from
        their tags' messages, docs/releases/before-*.txt)
    relnotes.py short --version V --notes FILE -o OUT
        UPDATE.LST's "what's new" (tools/mkmanifest.py --notes-file)
    relnotes.py tagmsg PKG --version V --notes FILE -o OUT
        the tag's message: the notes and the package's BUILT FROM
    relnotes.py prevrefs (--tag TAG | --pkg DIR) -o OUT
        the BUILT FROM of the release before (its tag's message, else its
        package's README)

Run from the top of the tree (git). MIT licence (see LICENSE)."""
import argparse
import os
import re
import subprocess
import sys
import textwrap

WIDTH = 72


def git(*a):
    return subprocess.run(('git',) + a, check=True, capture_output=True, text=True).stdout


def plain(s):
    """a title or a commit subject in plain words: no V-numbers, no asides"""
    s = s.replace('**', '').replace('`', '')
    # asides about the process: (V131, may be renumbered), (asked for: ...), (DECISIONS V71)
    for _ in range(3):
        s = re.sub(r'\s*\((?:[^()]*\b(?:V\d+|may be renumbered|asked for|DECISIONS|renumbered)\b[^()]*)\)', '', s)
    s = re.sub(r'\bV\d{2,3}(?:-V?\d{2,3})?\b,?\s*', '', s)
    s = re.sub(r'\s+', ' ', s).strip().rstrip('.;:,').strip()
    if len(s) > 220:                    # (a long one: cut at a clause)
        cut = max(s.rfind('; ', 0, 220), s.rfind(', ', 0, 220))
        s = s[:cut if cut > 80 else 220].rstrip() + ' ...'
    w = s.split(' ', 1)[0]
    return s[:1].upper() + s[1:] if w.isalpha() else s


def vnums(s):
    return set(re.findall(r'\bV(\d{2,3})\b', s))


def whats_new(since):
    rows = []
    diff = git('diff', '--unified=0', since, 'HEAD', '--', 'docs/DECISIONS.md')
    added_v = set()
    for l in diff.split('\n'):
        m = re.match(r'^\+\| V(\d+) \| \*\*(.+?)\*\*', l)
        if m:
            added_v.add(m.group(1))
            rows.append((int(m.group(1)), plain(m.group(2))))
    out = [t for _, t in sorted(rows)]
    seen = {t.lower() for t in out}
    for s in git('log', '--no-merges', '--reverse', '--format=%s', '%s..HEAD' % since).split('\n'):
        s = s.strip()
        if not s or s.startswith(('DECISIONS', 'Merge ', 'WIP', 'fixup!', 'squash!')) or re.match(r'(?i)^(gate|tests?)\b', s):
            continue
        if re.match(r'^Veranda \d+\.\d+(\.\d+)?$', s):     # (release.sh's own version commit)
            continue
        if vnums(s) & added_v:
            continue
        p = plain(s)
        if p and p.lower() not in seen:
            seen.add(p.lower())
            out.append(p)
    return out


def bullets(lines, indent='  '):
    out = []
    for l in lines:
        l = l.strip()
        if not l:
            continue
        l = l[2:] if l.startswith('- ') else l
        out += textwrap.wrap(l, WIDTH, initial_indent=indent + '- ', subsequent_indent=indent + '  ')
    return out


def read_notes(path):
    return [l.rstrip() for l in open(path, encoding='utf-8') if l.strip() and not l.startswith('#')]


def built_from(text):
    """the lines of a README's or a tag's BUILT FROM: {repository: hash}"""
    refs, on = {}, False
    for l in text.split('\n'):
        if l.strip() == 'BUILT FROM':
            on = True
            continue
        if on:
            if not l.startswith('  '):
                break
            m = re.match(r'^\s+(\S+) at \S+ \(([0-9a-f]+)\)', l)
            if m:
                refs[m.group(1)] = m.group(2)
            m = re.match(r'^\s+Veranda ([0-9a-f]+)', l)
            if m:
                refs['Veranda'] = m.group(1)
    return refs


def checklist(path, since, now_refs, prev_refs):
    secs, cur = [], None
    for l in open(path, encoding='utf-8'):
        l = l.rstrip('\n')
        if not l.strip() or l.startswith('#'):
            continue
        m = re.match(r'^\[([^\]]+)\]\s*(.*)$', l)
        if m:
            cur = {'name': m.group(1), 'src': m.group(2).split(), 'items': []}
            secs.append(cur)
        elif l.startswith('- '):
            cur['items'].append(l[2:])
        elif cur and cur['items']:
            cur['items'][-1] += ' ' + l.strip()
    for s in secs:
        new, why = False, []
        for src in s['src']:
            if src.startswith('sibling:'):
                r = src[8:]
                if r in now_refs and now_refs[r] != prev_refs.get(r):
                    new = True
                    why.append(r)
            else:
                if not os.path.exists(src):
                    print('relnotes: WARNING: tools/checklist.txt: [%s] names %s, which is not in the tree' % (
                        s['name'], src), file=sys.stderr)
                    continue
                if git('diff', '--stat', since, 'HEAD', '--', src).strip():
                    new = True
                    why.append(src)
        s['new'], s['why'] = new, why
    return secs


def cmd_readme(a):
    v = os.path.join(a.pkg, 'VERANDA')
    readme = os.path.join(v, 'README.txt')
    text = open(readme, encoding='latin-1').read()
    notes = read_notes(a.notes)
    now_refs = built_from(text)
    prev_refs = built_from(open(a.prev_refs, encoding='latin-1').read()) if a.prev_refs else {}
    since_s = git('rev-parse', '--short', a.since).strip()
    out = ['', 'NEW IN THIS BUILD: VERANDA %s (since %s)' % (a.version, since_s)]
    out += bullets(notes) or ['  (nothing but rebuilds)']
    out += ['  Earlier: VERANDA/CHANGES.txt.']
    if a.tilehw:
        out += ['', 'THE TILE TEST (/TILEHW, at the card\'s top)',
                '  A small test of VERA\'s 4 bpp tiles under the bitmap on the real X16',
                '  (what the desktop picture uses), outside Veranda. From BASIC:',
                '    DOS"CD:/TILEHW"', '    LOAD"TILEHW.PRG"', '    RUN',
                '  It alternates the old look and the new look every 8 seconds. Watch for',
                '  flicker, wrong colours, garbage tiles, a shifted picture.']
    if a.checklist:
        secs = checklist(a.checklist, a.since, now_refs, prev_refs)
        out += ['', 'THE HARDWARE CHECKLIST FOR %s' % a.version,
                '  NEW: changed since %s, try those first; the rest when there is time.' % since_s]
        for want in (True, False):
            for s in secs:
                if s['new'] != want:
                    continue
                for it in s['items']:
                    lead = '  [ ] %s%s: ' % ('NEW ' if want else '', s['name'])
                    out += textwrap.wrap(it, WIDTH, initial_indent=lead, subsequent_indent='      ')
        n = sum(1 for s in secs if s['new'])
        print('relnotes: the checklist: %d sections, %d NEW (%s)' % (
            len(secs), n, ', '.join(s['name'] for s in secs if s['new'])))
    with open(readme, 'a', encoding='latin-1', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
    # CHANGES.txt: this version, the versions before (their tags), the builds before the versions
    date = git('log', '-1', '--format=%cs', 'HEAD').strip()
    ch = ['VERANDA: WHAT CHANGED, VERSION BY VERSION', '',
          '%s (%s, build %s; since %s)' % (a.version, date, git('rev-parse', '--short', 'HEAD').strip(), since_s)]
    ch += bullets(notes) or ['  (nothing but rebuilds)']
    for t in git('tag', '-l', 'veranda-[0-9]*', '--sort=-v:refname').split():
        tv = t[len('veranda-'):]
        if tv == a.version:
            continue
        body = git('tag', '-l', '--format=%(contents)', t).split('\nBUILT FROM')[0].strip()
        when = git('log', '-1', '--format=%cs', t).strip()
        ch += ['', '%s (%s, build %s)' % (tv, when, git('rev-parse', '--short', t + '^{commit}').strip())]
        ch += bullets(read_notes_text(body))
    for f in sorted(os.listdir('docs/releases'), reverse=True) if os.path.isdir('docs/releases') else ():
        if f.startswith('before-') and f.endswith('.txt'):
            ch += ['', open(os.path.join('docs/releases', f), encoding='utf-8').read().rstrip()]
    with open(os.path.join(v, 'CHANGES.txt'), 'w', encoding='latin-1', errors='replace', newline='\n') as f:
        f.write('\n'.join(ch) + '\n')


def read_notes_text(body):
    out = []
    for l in body.split('\n'):
        l = l.rstrip()
        if not l:
            continue
        if l.startswith('- ') or not out:
            out.append(l)
        else:
            out[-1] += ' ' + l.strip()
    return out


def cmd_notes(a):
    lines = whats_new(a.since)
    text = ''.join('- %s\n' % l for l in lines)
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as f:
            f.write('# What\'s new in %s since %s (tools/relnotes.py; edit it and pass it as NOTES=...)\n'
                    % (a.version or 'this version', a.since))
            f.write(text)
    else:
        sys.stdout.write(text)


def cmd_short(a):
    lines = read_notes(a.notes)
    with open(a.out, 'w', encoding='utf-8') as f:
        f.write('Veranda %s:\n' % a.version)
        for l in lines:
            l = l[2:] if l.startswith('- ') else l
            f.write(l.split('; ')[0].rstrip('.') + '.\n')


def cmd_tagmsg(a):
    text = open(os.path.join(a.pkg, 'VERANDA', 'README.txt'), encoding='latin-1').read()
    bf = text.split('\nBUILT FROM\n', 1)
    tail = []
    if len(bf) == 2:
        for l in bf[1].split('\n'):
            if not l.startswith('  '):
                break
            tail.append(l)
    with open(a.out, 'w', encoding='utf-8') as f:
        f.write('Veranda %s\n\n' % a.version)
        for l in read_notes(a.notes):
            f.write((l if l.startswith('- ') else '- ' + l) + '\n')
        f.write('\nBUILT FROM\n' + '\n'.join(tail) + '\n')


def cmd_prevrefs(a):
    if a.tag:
        text = git('tag', '-l', '--format=%(contents)', a.tag)
    else:
        text = open(os.path.join(a.pkg, 'VERANDA', 'README.txt'), encoding='latin-1').read()
    refs = built_from(text)
    with open(a.out, 'w') as f:
        f.write('BUILT FROM\n')
        for k, h in refs.items():
            f.write('  Veranda %s\n' % h if k == 'Veranda' else '  %s at - (%s)\n' % (k, h))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('notes')
    p.add_argument('--since', required=True)
    p.add_argument('--version')
    p.add_argument('-o', '--out')
    p = sub.add_parser('readme')
    p.add_argument('pkg')
    p.add_argument('--version', required=True)
    p.add_argument('--since', required=True)
    p.add_argument('--notes', required=True)
    p.add_argument('--checklist')
    p.add_argument('--prev-refs')
    p.add_argument('--tilehw', action='store_true')
    p = sub.add_parser('short')
    p.add_argument('--version', required=True)
    p.add_argument('--notes', required=True)
    p.add_argument('-o', '--out', required=True)
    p = sub.add_parser('tagmsg')
    p.add_argument('pkg')
    p.add_argument('--version', required=True)
    p.add_argument('--notes', required=True)
    p.add_argument('-o', '--out', required=True)
    p = sub.add_parser('prevrefs')
    p.add_argument('--tag')
    p.add_argument('--pkg')
    p.add_argument('-o', '--out', required=True)
    a = ap.parse_args()
    {'notes': cmd_notes, 'readme': cmd_readme, 'short': cmd_short, 'tagmsg': cmd_tagmsg,
     'prevrefs': cmd_prevrefs}[a.cmd](a)


if __name__ == '__main__':
    main()
