#!/usr/bin/env python3
"""The privacy check of a public tree (DECISIONS V139, docs/PUBLISHING.md).

    pubscan.py <tree> [--private FILE] [--report] [--repo NAME]

<tree>: an exported folder (tools/publish.sh's git archive, minus the
private list). It fails (exit 1) when the tree still holds

  - a path that tools/publish.private names for this repository (the
    private files: DECISIONS.md, notes, memory files, the user's data);
  - a secret: an Anthropic, OpenAI or GitHub key or token, an AWS key, a
    private key block (the gates' made-up key sk-ant-gate-0000-dummy-...
    is allowed);
  - the user's home folder written out (/home/<user>/, /Users/<user>/);
  - a name of the user's own card files (tools/tocard.py's: TOCARD_KEEP,
    else ~/Projects/veranda-dist/tocard.keep, kept outside the tree), or
    the user's e-mail address (git config user.email).

and it lists (without failing) what only looks local, for the user to
read once: "~/Projects" and "$HOME/Projects" defaults (each one should
be a variable with that default) and private addresses (192.168.x.x). --report lists every hit of both kinds, file by file.

Standard library only. MIT licence (see LICENSE)."""
import argparse
import fnmatch
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PRIVATE = os.path.join(HERE, 'publish.private')
UNAMES = None

# never in a public tree (a hit fails the export)
SECRETS = [
    ('an Anthropic key', re.compile(rb'sk-ant-(?!gate-0000-dummy-)[A-Za-z0-9_-]{20,}')),
    ('an OpenAI key', re.compile(rb'sk-(?:proj-)?[A-Za-z0-9]{32,}')),
    ('a GitHub token', re.compile(rb'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}')),
    ('an AWS key', re.compile(rb'\bAKIA[0-9A-Z]{16}\b')),
    ('a private key', re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')),
    ('a home folder', re.compile(rb'/home/(?!runner\b|user\b|USER\b|<)[a-z_][a-z0-9_-]{1,31}/|/Users/(?!<)[A-Za-z][A-Za-z0-9_-]+/')),
]
# only local-looking: listed for the user, never fatal
LOCAL = [
    ('a ~/Projects default', re.compile(rb'(?:~|\$HOME|\$\{HOME\}|os\.path\.expanduser\(.~)/Projects')),
    ('a private address', re.compile(rb'\b192\.168\.\d{1,3}\.\d{1,3}\b')),
]


def user_names():
    """the user's own file names (tocard.py's list), as a regex, or None"""
    sys.path.insert(0, HERE)
    import tocard
    names = list(tocard.keep_names())
    try:                # your e-mail address (git's), never written into a public tree
        import subprocess
        mail = subprocess.run(['git', 'config', 'user.email'], capture_output=True, text=True).stdout.strip()
        if '@' in mail and not mail.endswith(('noreply.github.com', '.invalid')):
            names.append(mail.lower())
    except OSError:
        pass
    if not names:
        return None
    return re.compile(rb'(?i)(?<![\w.])(?:%s)(?![\w])' % b'|'.join(re.escape(n.encode()) for n in names))


def read_private(path, repo):
    """the globs tools/publish.private names for repo (and for every repository: '*')"""
    out = []
    with open(path, encoding='utf-8') as f:
        for l in f:
            l = l.split('#', 1)[0].strip()
            if not l:
                continue
            parts = l.split(None, 1)
            if len(parts) != 2:
                raise SystemExit('pubscan: %s: "%s" is not "<repository> <glob>"' % (path, l))
            if parts[0] in ('*', repo):
                out.append(parts[1].strip())
    return out


def matches(rel, globs):
    for g in globs:
        if g.endswith('/'):
            if rel.startswith(g) or ('/' + g) in ('/' + rel):
                return g
        elif fnmatch.fnmatchcase(rel, g) or fnmatch.fnmatchcase(os.path.basename(rel), g):
            return g
    return None


def scan(tree, globs):
    """(fatal, local): lists of (path, why)"""
    fatal, local = [], []
    for d, dirs, files in os.walk(tree):
        dirs[:] = sorted(x for x in dirs if x != '.git')
        for fn in sorted(files):
            p = os.path.join(d, fn)
            rel = os.path.relpath(p, tree).replace(os.sep, '/')
            g = matches(rel, globs)
            if g:
                fatal.append((rel, 'a private file (publish.private: %s)' % g))
                continue
            if os.path.islink(p):
                continue
            with open(p, 'rb') as f:
                data = f.read()
            if UNAMES is not None and UNAMES.search(data):
                fatal.append((rel, 'a name of the user\'s own files (tocard.keep) or the e-mail address'))
            for why, rx in SECRETS:
                m = rx.search(data)
                if m:
                    line = data.count(b'\n', 0, m.start()) + 1
                    fatal.append((rel, '%s, line %d' % (why, line)))
            for why, rx in LOCAL:
                n = len(rx.findall(data))
                if n:
                    local.append((rel, '%s (%d)' % (why, n)))
    return fatal, local


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('tree')
    ap.add_argument('--private', default=DEFAULT_PRIVATE)
    ap.add_argument('--repo', default='veranda')
    ap.add_argument('--report', action='store_true')
    a = ap.parse_args()
    global UNAMES
    UNAMES = user_names()
    globs = read_private(a.private, a.repo)
    fatal, local = scan(a.tree, globs)
    if a.report:
        for rel, why in local:
            print('pubscan: local   %s: %s' % (rel, why))
    else:
        kinds = {}
        for rel, why in local:
            kinds.setdefault(why.split(' (')[0], []).append(rel)
        for k, v in kinds.items():
            print('pubscan: %d files have %s (not fatal: see --report)' % (len(v), k))
    for rel, why in fatal:
        print('pubscan: PRIVATE %s: %s' % (rel, why))
    if fatal:
        print('pubscan: %s: %d private hits: not publishable' % (a.tree, len(fatal)))
        sys.exit(1)
    print('pubscan: %s (%s): nothing private' % (a.tree, a.repo))


if __name__ == '__main__':
    main()
