#!/bin/bash
# The Veranda manual (docs/manual) into a clone of the GitHub wiki
# (DECISIONS V134). It copies the pages and the pictures and fixes the
# links for the wiki; it does not commit or push: it prints the commands
# for you to run.
#
#   tools/mkwiki.sh [--repo OWNER/REPO] [--tree URL] <wiki-clone-dir>
#
#   <wiki-clone-dir>  a clone of the wiki: git clone https://github.com/OWNER/REPO.wiki.git
#   --repo            the repository whose wiki it is (veranda-x16/veranda):
#                     the pictures' addresses, raw.githubusercontent.com/wiki/OWNER/REPO/img/...
#   --tree            where this tree's files are on GitHub, for links out of
#                     docs/manual (default https://github.com/OWNER/REPO/blob/main,
#                     the public repository: this tree at its top, DECISIONS V139;
#                     sandlbn/veranda-x16 had it in veranda/: --tree .../blob/main/veranda)
#
# In the wiki every page is at the top: "Page.md" links become "Page"
# (GitHub's wiki links), "img/x.png" the picture's raw address in the wiki
# repository, "../..." links (the SDK, DECISIONS, VeraBASIC's manual)
# addresses in the tree on GitHub. Home.md and _Sidebar.md are the wiki's
# start page and navigation. Pages the wiki has but docs/manual does not
# are listed, not deleted.
set -e
HERE=$PWD
cd "$(dirname "$0")/.."
REPO=veranda-x16/veranda
TREE=
while [ $# -gt 1 ]; do
	case $1 in
	--repo) REPO=$2; shift 2 ;;
	--tree) TREE=$2; shift 2 ;;
	*) break ;;
	esac
done
[ $# -eq 1 ] || { sed -n '6,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
WIKI=$1
case $WIKI in /*) ;; *) WIKI=$HERE/$WIKI ;; esac   # (relative to where it was run)
[ -d "$WIKI" ] || { echo "mkwiki: no folder $WIKI (git clone https://github.com/$REPO.wiki.git first)" >&2; exit 1; }
[ -e "$WIKI/.git" ] || echo "mkwiki: WARNING: $WIKI is not a git clone" >&2
case $REPO in */*) ;; *) echo "mkwiki: --repo is OWNER/REPO" >&2; exit 2 ;; esac
[ -n "$TREE" ] || TREE=https://github.com/$REPO/blob/main
python3 -I -B - "$PWD/docs/manual" "$WIKI" "$REPO" "$TREE" <<'EOF'
import os, posixpath, re, shutil, sys
src, wiki, repo, tree = sys.argv[1:]
raw = 'https://raw.githubusercontent.com/wiki/%s/' % repo
pages = sorted(f for f in os.listdir(src) if f.endswith('.md'))

def fix(m):
    bang, text, target = m.group(1), m.group(2), m.group(3)
    if re.match(r'[a-z]+:', target) or target.startswith('#'):
        return m.group(0)
    path, _, frag = target.partition('#')
    if bang:
        return '%s[%s](%s%s)' % (bang, text, raw, path)
    if '/' not in path and path.endswith('.md'):
        if path not in pages:
            sys.exit('mkwiki: a link to %s, which is not a page' % target)
        return '[%s](%s%s)' % (text, path[:-3], '#' + frag if frag else '')
    rel = posixpath.normpath(posixpath.join('docs/manual', path))
    if rel.startswith('..'):
        sys.exit('mkwiki: a link out of the tree: %s' % target)
    return '[%s](%s/%s%s)' % (text, tree, rel, '#' + frag if frag else '')

os.makedirs(os.path.join(wiki, 'img'), exist_ok=True)
for f in pages:
    t = open(os.path.join(src, f), encoding='utf-8').read()
    t = re.sub(r'(!?)\[([^\]]*)\]\(([^)\s]+)\)', fix, t)
    with open(os.path.join(wiki, f), 'w', encoding='utf-8') as o:
        o.write(t)
imgs = sorted(os.listdir(os.path.join(src, 'img')))
for f in imgs:
    shutil.copyfile(os.path.join(src, 'img', f), os.path.join(wiki, 'img', f))
print('mkwiki: %d pages, %d pictures into %s' % (len(pages), len(imgs), wiki))
old = sorted(f for f in os.listdir(wiki) if f.endswith('.md') and f not in pages)
if old:
    print('mkwiki: the wiki also has these pages (not in docs/manual; delete them with git rm if they are old):')
    for f in old:
        print('    ' + f)
EOF
[ -n "$MKWIKI_QUIET" ] && exit 0
echo
echo "Now check and publish it yourself:"
echo "    cd $WIKI"
echo "    git status"
echo "    git add -A"
echo "    git commit -m \"The Veranda manual, from $(git rev-parse --short HEAD)\""
echo "    git push"
