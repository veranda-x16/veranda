#!/bin/bash
# tools/publish.sh against made-up repositories (DECISIONS V139): never
# GitHub. The organisation is a folder of bare repositories (ORG_URL=
# file://...), the sibling repositories are made up, and this tree is a
# copy of its files (committed or not) with a made-up release tag.
#
#   tests/test_publish.sh <work-dir>
#
#   1. --dry-run: the clones, exports, commits and tags in the work folder,
#      nothing pushed (every bare repository as it was)
#   2. 9.9.0: every repository gets one commit "Veranda 9.9.0" and the tag
#      v9.9.0; veranda's export without docs/DECISIONS.md, with the public
#      README and the workflows; a sibling's DECISIONS.md, CLAUDE.md and
#      __pycache__ left out, its CI workflow added; geochess pushed with
#      its history (the upstream author's commit kept) and one more commit
#      that removes c1541.exe; the site's workflow; the wiki's pages
#   3. 9.9.1: one more commit each, a sibling's body listing its commit
#      subjects since 9.9.0 (cleaned: no V-numbers, no "asked for"); an
#      unchanged sibling gets no commit, only the tag
#   4. refused, nothing pushed: a secret in a sibling's tree; a release
#      whose tag is on the organisation already; a port in the map
#   5. --test: the branch next, no tag
# MIT licence (see LICENSE).
set -e
cd "$(dirname "$0")/.."
TOP=$PWD
W=${1:?usage: tests/test_publish.sh <work-dir>}
rm -rf "$W"
mkdir -p "$W"
W=$(cd "$W" && pwd)
ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
g() { git -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# this tree: its files (tracked and new, not ignored) in a fresh repository
S=$W/src
mkdir -p "$S"
git ls-files -z -co --exclude-standard | tar --null -T - -cf - | tar -x -C "$S"
# (the public repository has no decisions log: a made-up one, to be left out)
[ -f "$S/docs/DECISIONS.md" ] || echo "private: made up" > "$S/docs/DECISIONS.md"
g -C "$S" init -q
g -C "$S" add -A
g -C "$S" commit -q -m "Veranda as it is"
[ -f "$S/docs/DECISIONS.md" ] || fail "the copy has no docs/DECISIONS.md"

# the sibling repositories, made up: one file each, plus private ones
PR=$W/projects
mk() {           # $1 the tree's name, $2.. extra files
	local d=$PR/$1
	mkdir -p "$d"
	g -C "$d" init -q
	echo "# $1" > "$d/README.md"
	echo "MIT License (made up)" > "$d/LICENSE"
	shift
	for f in "$@"; do
		mkdir -p "$d/$(dirname "$f")"
		echo "private: $f" > "$d/$f"
	done
	g -C "$d" add -A
	g -C "$d" commit -q -m "the first version (V12, asked for: a test)"
}
mk commander-write DECISIONS.md CLAUDE.md tools/__pycache__/x.pyc
mk commander-calc
mk veranda-pinball
mk harbour-walls
mk veranda-sidplay
mk veranda-solitaire
mk x16-mod PLAN.md docs/decisions.md docs/original-brief.md
# geochess: an upstream author's commit, then the port's
mkdir -p "$PR/veranda-geochess"
g -C "$PR/veranda-geochess" init -q
echo "geoChess" > "$PR/veranda-geochess/README.md"
echo "binary" > "$PR/veranda-geochess/c1541.exe"
g -C "$PR/veranda-geochess" add -A
GIT_AUTHOR_NAME="Upstream Author" g -C "$PR/veranda-geochess" commit -q -m "geoChess upstream"
g -C "$PR/veranda-geochess" checkout -q -b veranda
echo "port" > "$PR/veranda-geochess/port.c"
g -C "$PR/veranda-geochess" add -A
g -C "$PR/veranda-geochess" commit -q -m "the Veranda port"
# the emulator with the modem back-end: a branch modem (history mode)
mkdir -p "$PR/x16-emulator-modem"
g -C "$PR/x16-emulator-modem" init -q
echo "x16emu" > "$PR/x16-emulator-modem/README.md"
g -C "$PR/x16-emulator-modem" add -A
GIT_AUTHOR_NAME="Emulator Author" g -C "$PR/x16-emulator-modem" commit -q -m "x16emu upstream"
g -C "$PR/x16-emulator-modem" checkout -q -b modem
echo "modem" > "$PR/x16-emulator-modem/modem.c"
g -C "$PR/x16-emulator-modem" add -A
g -C "$PR/x16-emulator-modem" commit -q -m "a Zimodem back-end"

# the release tag, as tools/release.sh writes it
tagmsg() {       # $1 version
	echo "- A made-up point of $1 (V999, asked for: nothing)"
	echo "- Another point"
	echo
	echo "BUILT FROM"
	echo "  Veranda $(g -C "$S" rev-parse --short HEAD)"
	for r in commander-write commander-calc veranda-pinball harbour-walls veranda-sidplay veranda-solitaire x16-mod veranda-geochess; do
		echo "  $r at main ($(g -C "$PR/$r" rev-parse --short HEAD))"
	done
}
tagmsg 9.9.0 > "$W/tag.txt"
g -C "$S" tag -a veranda-9.9.0 -F "$W/tag.txt"

# the organisation: bare repositories (geochess and the wiki with a first commit, as GitHub makes them)
O=$W/org
mkdir -p "$O"
for r in veranda veranda-write commander-calc lighthouse-pinball harbour-walls veranda-sidplay veranda-solitaire mod-player geochess x16-emulator veranda-x16.github.io veranda.wiki; do
	g init -q --bare "$O/$r.git"
done
g clone -q "$O/geochess.git" "$W/fork" 2>/dev/null
g -C "$W/fork" fetch -q "$PR/veranda-geochess" main
g -C "$W/fork" push -q origin FETCH_HEAD:refs/heads/main
g clone -q "$O/veranda.wiki.git" "$W/wk" 2>/dev/null
echo "Welcome" > "$W/wk/Home.md"
g -C "$W/wk" add -A
g -C "$W/wk" commit -q -m "Initial Home page"
g -C "$W/wk" branch -q -m master
g -C "$W/wk" push -q origin master
state() { for r in "$O"/*.git; do echo "$r $(g -C "$r" for-each-ref --format='%(refname) %(objectname)' | tr '\n' ' ')"; done; }
export ORG=veranda-x16 ORG_URL=file://$O VERANDA_PROJECTS=$PR DIST=$W/dist
pub() { "$S/tools/publish.sh" --yes "$@"; }

# 1. a dry run
before=$(state)
pub --dry-run 9.9.0 > "$W/1.log" 2>&1 || { tail -30 "$W/1.log"; fail "1: the dry run"; }
[ "$before" = "$(state)" ] || fail "1: the dry run pushed something"
grep -q '(dry run, not run) git -C .*/veranda push origin refs/heads/main:refs/heads/main refs/tags/v9.9.0' "$W/1.log" ||
	{ tail -20 "$W/1.log"; fail "1: no push printed for veranda"; }
[ "$(g -C "$W/dist/publish/9.9.0/veranda" log -1 --format=%s)" = "Veranda 9.9.0" ] || fail "1: no commit in the work clone"
ok "--dry-run: 12 repositories cloned, exported, checked, committed and tagged in the work folder; each push printed, none run"

# 2. 9.9.0
pub 9.9.0 > "$W/2.log" 2>&1 || { tail -30 "$W/2.log"; fail "2: 9.9.0"; }
C=$W/check
rm -rf "$C"
g clone -q "$O/veranda.git" "$C/veranda"
[ "$(g -C "$C/veranda" log --format=%s main)" = "Veranda 9.9.0" ] || fail "2: veranda's history: $(g -C "$C/veranda" log --format=%s main)"
[ "$(g -C "$C/veranda" rev-parse 'v9.9.0^{commit}')" = "$(g -C "$C/veranda" rev-parse main)" ] || fail "2: veranda's tag"
[ ! -e "$C/veranda/docs/DECISIONS.md" ] || fail "2: DECISIONS.md was published"
cmp -s "$C/veranda/README.md" "$S/tools/publish/veranda/README.md" || fail "2: veranda's README is not the public one"
[ -f "$C/veranda/.github/workflows/release.yml" ] && [ -f "$C/veranda/tools/publish.sh" ] || fail "2: veranda's workflows or tools"
g -C "$C/veranda" log -1 --format=%B | grep -q "^- A made-up point of 9.9.0$" || fail "2: the notes (cleaned) in veranda's commit"
g -C "$C/veranda" log -1 --format=%B | grep -q "^Veranda-Source: Veranda $(g -C "$S" rev-parse HEAD)$" || fail "2: the trailer"
g clone -q "$O/veranda-write.git" "$C/cw"
[ -f "$C/cw/README.md" ] && [ ! -e "$C/cw/DECISIONS.md" ] && [ ! -e "$C/cw/CLAUDE.md" ] && [ ! -e "$C/cw/tools/__pycache__" ] ||
	fail "2: commander-write's private files: $(cd "$C/cw" && find . -path ./.git -prune -o -type f -print | tr '\n' ' ')"
grep -q 'make veranda SDK="$SDK"' "$C/cw/.github/workflows/veranda-ci.yml" || fail "2: commander-write's CI workflow"
g clone -q "$O/mod-player.git" "$C/mp"
[ ! -e "$C/mp/PLAN.md" ] && [ ! -e "$C/mp/docs/decisions.md" ] && [ ! -e "$C/mp/docs/original-brief.md" ] || fail "2: mod-player's notes"
g clone -q -b veranda "$O/geochess.git" "$C/gc"
[ "$(g -C "$C/gc" log --format='%an|%s' | tr '\n' ';')" = "Test|Veranda 9.9.0;Test|the Veranda port;Upstream Author|geoChess upstream;" ] ||
	fail "2: geochess's history: $(g -C "$C/gc" log --format='%an|%s' | tr '\n' ';')"
[ ! -e "$C/gc/c1541.exe" ] && [ -f "$C/gc/port.c" ] || fail "2: geochess's tip"
g -C "$C/gc" rev-parse -q --verify 'refs/tags/v9.9.0' >/dev/null || fail "2: geochess's tag"
[ "$(g -C "$O/x16-emulator.git" log --format=%s modem | tr '\n' ';')" = "a Zimodem back-end;x16emu upstream;" ] ||
	fail "2: x16-emulator's branch modem: $(g -C "$O/x16-emulator.git" log --format=%s modem | tr '\n' ';')"
g clone -q "$O/veranda-x16.github.io.git" "$C/site"
[ -f "$C/site/.github/workflows/pages.yml" ] || fail "2: the site's workflow"
g clone -q "$O/veranda.wiki.git" "$C/wiki"
[ -f "$C/wiki/Home.md" ] && [ -f "$C/wiki/Installing.md" ] && [ -f "$C/wiki/_Sidebar.md" ] && ls "$C/wiki/img/"*.png >/dev/null ||
	fail "2: the wiki's pages"
grep -q 'raw.githubusercontent.com/wiki/veranda-x16/veranda/img/' "$C/wiki/Home.md" || fail "2: the wiki's pictures' addresses"
for r in lighthouse-pinball harbour-walls veranda-sidplay veranda-solitaire commander-calc; do
	[ "$(g -C "$O/$r.git" log --format=%s main)" = "Veranda 9.9.0" ] || fail "2: $r"
done
ok "9.9.0: one commit \"Veranda 9.9.0\" and the tag v9.9.0 in each of 10 repositories; DECISIONS.md, CLAUDE.md, __pycache__, mod-player's notes left out; the public README; the siblings' CI; geochess with its upstream author's commit and c1541.exe removed; the site's workflow; the wiki (45 pages, the pictures' wiki addresses)"

# 3. 9.9.1: commander-write changed twice, the others not
echo "more" >> "$PR/commander-write/README.md"
g -C "$PR/commander-write" commit -q -am "Styles (V200, asked for: headings); the ruler"
echo "more" >> "$PR/commander-write/LICENSE"
g -C "$PR/commander-write" commit -q -am "Find and replace"
echo "more port" >> "$PR/veranda-geochess/port.c"
g -C "$PR/veranda-geochess" commit -q -am "the port, more"
echo "x" > "$S/NEWFILE.txt"
g -C "$S" add -A
g -C "$S" commit -q -m "a change"
tagmsg 9.9.1 > "$W/tag.txt"
g -C "$S" tag -a veranda-9.9.1 -F "$W/tag.txt"
pub --no-wiki 9.9.1 > "$W/3.log" 2>&1 || { tail -30 "$W/3.log"; fail "3: 9.9.1"; }
[ "$(g -C "$O/veranda-write.git" log --format=%s main | tr '\n' ';')" = "Veranda 9.9.1;Veranda 9.9.0;" ] || fail "3: commander-write's history"
body=$(g -C "$O/veranda-write.git" log -1 --format=%B main)
echo "$body" | grep -q '^- Styles; the ruler$' && echo "$body" | grep -q '^- Find and replace$' || fail "3: commander-write's body: $body"
[ "$(g -C "$O/commander-calc.git" log --format=%s main | tr '\n' ';')" = "Veranda 9.9.0;" ] || fail "3: an unchanged sibling got a commit"
[ "$(g -C "$O/commander-calc.git" rev-parse 'v9.9.1^{commit}')" = "$(g -C "$O/commander-calc.git" rev-parse main)" ] || fail "3: its tag"
[ "$(g -C "$O/veranda.git" log --format=%s main | tr '\n' ';')" = "Veranda 9.9.1;Veranda 9.9.0;" ] || fail "3: veranda's history"
g clone -q -b veranda "$O/geochess.git" "$C/gc2"
[ "$(g -C "$C/gc2" log --first-parent --format=%s | tr '\n' ';')" = "Veranda 9.9.1;Veranda 9.9.0;the Veranda port;geoChess upstream;" ] &&
	g -C "$C/gc2" log --format=%s | grep -q '^the port, more$' && [ ! -e "$C/gc2/c1541.exe" ] && grep -q 'more port' "$C/gc2/port.c" ||
	fail "3: geochess: $(g -C "$C/gc2" log --format=%s | tr '\n' ';')"
ok "9.9.1: one more commit where the tree changed, its body the source's subjects since 9.9.0 (cleaned); an unchanged sibling only tagged; geochess's new commit merged in (its author's commit kept, c1541.exe still out, never forced)"

# 4. refused
before=$(state)
k=sk-ant; echo "key = '$k-api03-abcdefghijklmnopqrstuvwxyz0123456789'" > "$PR/harbour-walls/conf.py"
g -C "$PR/harbour-walls" add -A
g -C "$PR/harbour-walls" commit -q -m "a key by mistake"
tagmsg 9.9.2 > "$W/tag.txt"
g -C "$S" tag -a veranda-9.9.2 -F "$W/tag.txt"
set +e
pub --only harbour-walls 9.9.2 > "$W/4a.log" 2>&1
rc=$?
pub --only commander-calc 9.9.1 > "$W/4b.log" 2>&1
rc2=$?
set -e
[ $rc != 0 ] && grep -q 'PRIVATE conf.py: an Anthropic key' "$W/4a.log" || { tail "$W/4a.log"; fail "4: a secret was not refused"; }
[ $rc2 != 0 ] && grep -q 'the tag v9.9.1 is on GitHub already' "$W/4b.log" || { tail "$W/4b.log"; fail "4: a published tag again"; }
[ "$before" = "$(state)" ] || fail "4: something was pushed"
cp "$S/tools/publish.repos" "$W/repos.bak"
echo "geowrite | veranda-geowrite | veranda-geowrite | main | export | main | x | - | -" >> "$S/tools/publish.repos"
set +e
pub --only geowrite 9.9.2 > "$W/4c.log" 2>&1
rc=$?
set -e
cp "$W/repos.bak" "$S/tools/publish.repos"
[ $rc != 0 ] && grep -q 'never published' "$W/4c.log" || { tail "$W/4c.log"; fail "4: a port in the map"; }
[ "$before" = "$(state)" ] || fail "4: something was pushed"
ok "refused, nothing pushed: an Anthropic key in a sibling's tree; a tag the organisation has; geoWrite in the map"
g -C "$PR/harbour-walls" reset -q --hard HEAD~1

# 5. --test (a change since 9.9.1)
echo "y" > "$S/NEWFILE.txt"
g -C "$S" commit -q -am "a change after 9.9.1"
pub --test --only "veranda veranda-write" > "$W/5.log" 2>&1 || { tail -30 "$W/5.log"; fail "5: --test"; }
[ "$(g -C "$O/veranda.git" log -1 --format=%s next)" = "Veranda test build $(g -C "$S" rev-parse --short main)" ] || fail "5: veranda's next"
g -C "$O/veranda.git" merge-base --is-ancestor main next || fail "5: next does not start from main"
[ "$(g -C "$O/veranda-write.git" rev-parse -q --verify refs/heads/next)" ] || fail "5: commander-write's next"
[ "$(g -C "$O/veranda.git" tag -l | tr '\n' ' ')" = "v9.9.0 v9.9.1 " ] || fail "5: a tag was made: $(g -C "$O/veranda.git" tag -l)"
ok "--test: the branch next (from main), \"Veranda test build <hash>\", no tag"
echo "TEST publish: PASS"
