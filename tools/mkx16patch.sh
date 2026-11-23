#!/bin/bash
# The public repository's next patch (docs/RELEASING.md): veranda-x16 as it
# will be after the patches made so far, plus this tree's changes since the
# commit the last patch was made from, as one more `git format-patch` file.
#
#   tools/mkx16patch.sh <work> <out-dir> [<version>]
#
# <work>: a new scratch folder (the clone and the trees go there);
# <out-dir>: where the patch goes (NNNN-<subject>.patch, numbered after the
# last one in $PATCHES and <out-dir>). Never writes to ~/Projects/veranda-x16:
# it clones it.
#
#   X16=~/Projects/veranda-x16                 the public repository (read)
#   PATCHES=~/Projects/veranda-dist/patches/veranda-x16
#                                              the patches made so far: each
#                                              one its history lacks (by its
#                                              subject) is applied with git am
#   X16_BASE=<commit>                          this tree's commit the last
#                                              patch was made from; default:
#                                              the last "Veranda-Source:"
#                                              trailer in the clone's history,
#                                              else 9277017 (patch 0021)
#   X16_GATES="about update"                   the gates run in the clone
#                                              (veranda/tools/gate_<name>.sh)
#   NOTES=<file>                               the commit message's bullets
#
# The diff: every file this tree changed since X16_BASE, under veranda/,
# but docs/DECISIONS.md, README.md and docs/releases/ (this tree's own:
# veranda-x16 has its own README and keeps no decision log). Each file:
#   - veranda-x16's copy as X16_BASE had it (or none, for a new file): this
#     tree's new one, whole;
#   - tools/mkdist.sh: this tree's, whole (it builds veranda-x16's ../apps
#     itself: MONO in it), whatever veranda-x16 has;
#   - else a three-way merge (git merge-file: X16_BASE's, veranda-x16's,
#     this tree's); a conflict, a binary file both changed, or a file
#     veranda-x16 deleted that this tree changed stops it, nothing made.
# The top-level Makefile's VAPPS: the folders veranda/tools/mkdist.sh builds
# with app (and vbasic), in the order the list had, new ones at the end.
# README.md: the programs it does not name are listed for you to add.
# Then: make build, make dist (no port may be in dist/), the gates.
set -e
cd "$(dirname "$0")/.."
TOP=$PWD
[ -n "$2" ] || { echo "usage: tools/mkx16patch.sh <work> <out-dir> [<version>]" >&2; exit 2; }
WORK=$1
OUTD=$2
VER=${3:-$(cat VERSION 2>/dev/null || echo 0.0.0)}
X16=${X16:-$HOME/Projects/veranda-x16}
PATCHES=${PATCHES:-$HOME/Projects/veranda-dist/patches/veranda-x16}
X16_GATES=${X16_GATES:-about update}
say() { echo "mkx16patch: $*"; }
die() { echo "mkx16patch: $*" >&2; exit 1; }

[ ! -e "$WORK" ] || die "$WORK is there already (a new folder)"
mkdir -p "$WORK" "$OUTD"
WORK=$(cd "$WORK" && pwd)
OUTD=$(cd "$OUTD" && pwd)
C=$WORK/x16
git clone -q "$X16" "$C" || die "git clone $X16"
# (your git identity: no address written into the tree; DECISIONS V139)
NAME=$(git config user.name) || die "git config user.name: not set"
MAIL=$(git config user.email) || die "git config user.email: not set"
G() { git -C "$C" -c user.name="$NAME" -c user.email="$MAIL" "$@"; }

# 1. the patches made so far, those its history lacks
G log --format=%s > "$WORK/subjects.txt"
n=0
for p in "$PATCHES"/[0-9][0-9][0-9][0-9]-*.patch; do
	[ -f "$p" ] || continue
	s=$(sed -n '/^Subject: /{s/^Subject: \(\[PATCH[^]]*\] \)\{0,1\}//;p;q}' "$p")
	if grep -qxF -- "$s" "$WORK/subjects.txt"; then
		continue
	fi
	# (a subject longer than a line is folded in the file: match its start)
	if grep -qF -- "${s:0:60}" "$WORK/subjects.txt"; then
		continue
	fi
	G am -q --whitespace=nowarn "$p" || die "git am $p does not apply (git -C $C am --abort)"
	n=$((n + 1))
done
say "veranda-x16 $(G rev-parse --short HEAD) with $n of the patches in $PATCHES applied"

# 2. the commit the last patch was made from
BASE=${X16_BASE:-$(G log --format=%B | sed -n 's/^Veranda-Source: \([0-9a-f]\{7,40\}\).*/\1/p' | head -1)}
BASE=${BASE:-9277017}
git rev-parse -q --verify "$BASE^{commit}" >/dev/null || die "X16_BASE $BASE: not a commit of this tree"
HEADC=$(git rev-parse --short HEAD)
say "this tree's changes since $(git rev-parse --short "$BASE") (the last patch's source) up to $HEADC"
mkdir -p "$WORK/base" "$WORK/head"
git archive "$BASE" | tar -x -C "$WORK/base"
git archive HEAD | tar -x -C "$WORK/head"

# 3. the files
excluded() {
	case $1 in
	docs/DECISIONS.md | README.md | docs/releases/*) return 0 ;;
	esac
	return 1
}
: > "$WORK/conflicts.txt"
: > "$WORK/changes.txt"
git diff --name-status --no-renames "$BASE" HEAD > "$WORK/names.txt"
while IFS=$'\t' read -r st path; do
	excluded "$path" && { echo "excluded  $path" >> "$WORK/changes.txt"; continue; }
	d=$C/veranda/$path b=$WORK/base/$path h=$WORK/head/$path
	case $st in
	D)
		if [ ! -e "$d" ]; then
			:
		elif cmp -s "$d" "$b"; then
			G rm -q "veranda/$path"
			echo "deleted   $path" >> "$WORK/changes.txt"
		else
			echo "$path: deleted here, changed in veranda-x16" >> "$WORK/conflicts.txt"
		fi
		;;
	A | M)
		if [ ! -e "$d" ] && [ "$st" = M ]; then
			echo "$path: changed here, deleted in veranda-x16" >> "$WORK/conflicts.txt"
		elif [ ! -e "$d" ] || cmp -s "$d" "$b" || [ "$path" = tools/mkdist.sh ]; then
			mkdir -p "$(dirname "$d")"
			cp -p "$h" "$d"
			echo "taken     $path" >> "$WORK/changes.txt"
		elif cmp -s "$d" "$h"; then
			:
		elif [ "$st" = A ]; then
			echo "$path: new here, another file of that name in veranda-x16" >> "$WORK/conflicts.txt"
		elif ! grep -qI . "$h" || ! grep -qI . "$d"; then
			echo "$path: a binary file changed in both" >> "$WORK/conflicts.txt"
		else
			cp "$d" "$WORK/ours"
			if git merge-file -q -L veranda-x16 -L "$(git rev-parse --short "$BASE")" -L "$HEADC" \
				"$WORK/ours" "$b" "$h"; then
				cp "$WORK/ours" "$d"
				chmod --reference="$h" "$d"
				echo "merged    $path (veranda-x16's own changes kept)" >> "$WORK/changes.txt"
			else
				echo "$path: a three-way merge conflict" >> "$WORK/conflicts.txt"
			fi
		fi
		;;
	*) echo "$path: status $st" >> "$WORK/conflicts.txt" ;;
	esac
done < "$WORK/names.txt"
if [ -s "$WORK/conflicts.txt" ]; then
	sed 's/^/  CONFLICT /' "$WORK/conflicts.txt" >&2
	die "conflicts (above): nothing made; resolve them in $C by hand, or set X16_BASE"
fi
say "$(grep -c '^taken' "$WORK/changes.txt" || true) files taken, $(grep -c '^merged' "$WORK/changes.txt" || true) merged, $(grep -c '^deleted' "$WORK/changes.txt" || true) deleted, $(grep -c '^excluded' "$WORK/changes.txt" || true) left out"

# 4. the Makefile's VAPPS, from veranda/tools/mkdist.sh
want=$( (sed -n 's|^app apps/\([^ ]*\) .*|\1|p' "$C/veranda/tools/mkdist.sh"; echo vbasic) | awk '!s[$0]++')
have=$(sed -n 's/^VAPPS := //p' "$C/Makefile")
[ -n "$have" ] || die "veranda-x16's Makefile has no VAPPS line"
new=""
for a in $have; do echo "$want" | grep -qx "$a" && new="$new $a"; done
for a in $want; do echo " $new " | grep -q " $a " || new="$new $a"; done
new=${new# }
added=""
for a in $new; do echo " $have " | grep -q " $a " || added="$added $a"; done
if [ "$new" != "$have" ]; then
	sed -i "s/^VAPPS := .*/VAPPS := $new/" "$C/Makefile"
	say "Makefile: VAPPS := $new"
fi
for a in $want; do
	[ -f "$C/veranda/apps/$a/Makefile" ] || die "VAPPS: veranda/apps/$a has no Makefile"
done
# README.md: the programs new in VAPPS it does not name (by their names on the card)
: > "$WORK/readme-missing.txt"
for a in $added; do
	grep "^app apps/$a " "$C/veranda/tools/mkdist.sh" | grep -o '"[^"=]*=[^"]*\.cvt"' |
		sed 's/^"[^=]*=\(.*\)\.cvt"$/\1/' | while read -r name; do
		grep -qiF -- "$name" "$C/README.md" || echo "$name (apps/$a)"
	done >> "$WORK/readme-missing.txt"
done
if [ -s "$WORK/readme-missing.txt" ]; then
	say "README.md does not name these new programs (add a bullet by hand: git commit --amend in $C, format-patch again):"
	sed 's/^/    /' "$WORK/readme-missing.txt"
fi
# veranda-x16's apps/ beside the sibling repositories they came from
P=${VERANDA_PROJECTS:-$HOME/Projects}   # (the sibling repositories' folder)
for m in calc:commander-calc:layout modplayer:x16-mod:layout solitaire:veranda-solitaire:layout \
	pinball:veranda-pinball:master harbour-walls:harbour-walls:master sidplay:veranda-sidplay:main; do
	IFS=: read -r dir repo ref <<< "$m"
	[ -d "$C/apps/$dir" ] && [ -d "$P/$repo" ] || continue
	git -C "$P/$repo" rev-parse -q --verify "$ref^{commit}" >/dev/null || continue
	rm -rf "$WORK/sib" && mkdir -p "$WORK/sib"
	git -C "$P/$repo" archive "$ref" | tar -x -C "$WORK/sib"
	k=$(diff -rq -x build "$WORK/sib" "$C/apps/$dir" 2>/dev/null | wc -l)
	if [ "$k" = 0 ]; then
		echo "apps/$dir: the same as $repo $ref" >> "$WORK/apps.txt"
	else
		echo "apps/$dir: $k files not as $repo $ref ($(git -C "$P/$repo" rev-parse --short "$ref")) has them: veranda-x16's own changes, or newer ones to bring in by hand" >> "$WORK/apps.txt"
	fi
done
[ -f "$WORK/apps.txt" ] && sed 's/^/mkx16patch: /' "$WORK/apps.txt"

# 5. the commit, the patch
G add -A
if G diff --cached --quiet; then
	say "nothing to patch: veranda-x16 already has this tree's changes"
	exit 0
fi
{
	echo "Veranda $VER ($(git log -1 --format=%cs HEAD), build $HEADC)"
	echo
	if [ -n "$NOTES" ] && [ -f "$NOTES" ]; then
		grep -v '^#' "$NOTES" | sed '/^$/d' | fold -s -w 74 | sed 's/^\([^-]\)/  \1/'
		echo
	fi
	echo "Veranda-Source: $(git rev-parse HEAD)"
	echo
	echo "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
} > "$WORK/msg.txt"
G commit -q -F "$WORK/msg.txt"
last=$( (ls "$PATCHES" "$OUTD" 2>/dev/null) | sed -n 's/^\([0-9]\{4\}\)-.*\.patch$/\1/p' | sort -n | tail -1)
num=$((10#${last:-0} + 1))
f=$(G format-patch --binary -1 --start-number "$num" -o "$OUTD" HEAD)
say "the patch: $f ($(wc -c < "$f") bytes)"
echo "$f" > "$WORK/patch.txt"

# 6. built and gated in the clone
if [ "${X16_BUILD:-1}" = 1 ]; then
	say "make build, make dist in $C"
	make -C "$C" -j"$(nproc)" build > "$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log"; die "the clone does not build ($WORK/build.log)"; }
	make -C "$C" dist > "$WORK/dist.log" 2>&1 || { tail -20 "$WORK/dist.log"; die "the clone's make dist ($WORK/dist.log)"; }
	if ls "$C/dist/VERANDA/APPS" | grep -qi 'geowrite\|topdesk\|geochess'; then
		die "a port in the clone's dist/: $(ls "$C/dist/VERANDA/APPS" | grep -i 'geowrite\|topdesk\|geochess')"
	fi
	say "dist/: $(find "$C/dist" -type f | wc -l) files, $(ls "$C/dist/VERANDA/APPS" | wc -l) in APPS, no port"
	for g in $X16_GATES; do
		if (cd "$C/veranda" && "tools/gate_$g.sh") > "$WORK/gate_$g.log" 2>&1; then
			say "gate $g in the clone: PASS"
		else
			tail -5 "$WORK/gate_$g.log"
			die "gate $g in the clone: FAIL ($WORK/gate_$g.log)"
		fi
	done
fi
say "done: $f; apply it with: git -C $X16 am $f"
