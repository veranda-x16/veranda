#!/bin/bash
# Publish a Veranda release to the GitHub organisation veranda-x16
# (docs/PUBLISHING.md, DECISIONS V139). You run it, after tools/release.sh.
#
#   tools/publish.sh [options] <version>        e.g. tools/publish.sh 1.0
#   tools/publish.sh [options] --test [<ref>]   a test build (default: main)
#
# For each repository of tools/publish.repos (the sibling repositories
# first, veranda last, whose tag starts the release workflow):
#   1. a clone of the organisation's repository in the work folder
#      ($ORG_URL/<repo>.git; a new, empty repository is fine);
#   2. the public tree: git archive of the commit the release was built
#      from (this tree: the tag veranda-<version>; a sibling: the commit its
#      BUILT FROM names), minus tools/publish.private, plus the files
#      tools/publish/ adds (veranda's public README; a sibling's CI
#      workflow), checked by tools/pubscan.py (nothing private, no secret,
#      no home folder);
#   3. one commit "Veranda <version>" with the notes (veranda) or the
#      source's commit subjects since the last publish (the others), and
#      the trailer "Veranda-Source: <key> <hash>"; nothing when the tree is
#      the same (the tag goes on the commit there);
#   4. the annotated tag v<version>;
#   5. the push: git push origin <branch> v<version> (your credentials).
# geochess (mode history) is pushed with its history instead, so Scott
# Hutter's and the other authors' commits stay theirs; a private file at
# its tip is removed by one more commit.
# Then the site's repository (veranda-x16.github.io: its workflow and
# README from tools/publish/site), and the wiki (tools/mkwiki.sh into
# veranda.wiki.git).
#
# --test: the "next" branch of each repository instead of main, no tag;
# this tree at <ref> and the siblings at the refs tools/mkdist.sh builds.
# The push of veranda's next branch starts the test workflow, which
# replaces the assets of the pre-release tagged "test" (Veranda Update's
# Test channel; the branch is not called test, so that the tag and the
# branch do not share a name).
#
# Options:
#   --dry-run       everything but the pushes: the clones, the exports, the
#                   checks, the commits and tags in the work folder; prints
#                   each push it would run and each commit's files
#   --only "a b"    only these repositories (names of tools/publish.repos,
#                   site, wiki)
#   --no-wiki       not the wiki      --no-site    not the site's repository
#   --yes           no question before each repository's push
#
# Environment:
#   ORG=veranda-x16                     the organisation
#   ORG_URL=https://github.com/$ORG     where its repositories are (git@github.com:$ORG
#                                       for SSH; a file:///folder of bare repositories
#                                       for a test: tests/test_publish.sh)
#   DIST=~/Projects/veranda-dist        the work folder: $DIST/publish/<version>/
#   VERANDA_PROJECTS=~/Projects         where the sibling repositories are
#
# It never force-pushes, never deletes a branch or a tag, and never talks
# to GitHub's API: the pushes are plain git pushes, which you can stop with
# Ctrl+C before each (it waits for Return between repositories unless
# --yes or --dry-run).
set -e
cd "$(dirname "$0")/.."
TOP=$PWD
PY="python3 -I -B"
DRY=0 TEST=0 ONLY="" WIKI=1 SITE=1 YES=0
while [ $# -gt 0 ]; do
	case $1 in
	--dry-run) DRY=1 ;;
	--test) TEST=1 ;;
	--only) shift; ONLY=" $1 " ;;
	--no-wiki) WIKI=0 ;;
	--no-site) SITE=0 ;;
	--yes) YES=1 ;;
	-h | --help) sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	-*) echo "publish: unknown option $1" >&2; exit 2 ;;
	*) break ;;
	esac
	shift
done
ORG=${ORG:-veranda-x16}
ORG_URL=${ORG_URL:-https://github.com/$ORG}
DIST=${DIST:-$HOME/Projects/veranda-dist}
P=${VERANDA_PROJECTS:-$HOME/Projects}
say() { echo "publish: $*"; }
die() { echo "publish: STOPPED: $*" >&2; exit 1; }
step() { echo "  + $*"; "$@"; }                  # a step, printed, run
push() {                                         # a push: printed; run unless --dry-run
	if [ "$DRY" = 1 ]; then
		echo "  (dry run, not run) $*"
	else
		echo "  + $*"
		"$@"
	fi
}
want() { [ -z "$ONLY" ] || [[ "$ONLY" == *" $1 "* ]]; }

if [ "$TEST" = 1 ]; then
	REF=${1:-main}
	SRC=$(git rev-parse --verify -q "$REF^{commit}") || die "--test $REF: not a commit here"
	SHORT=$(git rev-parse --short "$SRC")
	VER="test-$SHORT"
	say "a test build of $REF ($SHORT) to the next branches of $ORG_URL"
else
	VER=$1
	[ -n "$VER" ] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
	echo "$VER" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?(-[0-9A-Za-z]{1,6})?$' || die "version $VER: N.M or N.M.P"
	TAG=veranda-$VER
	git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "no tag $TAG here (tools/release.sh $VER makes it)"
	SRC=$(git rev-parse "$TAG^{commit}")
	SHORT=$(git rev-parse --short "$SRC")
	VTAG=v$VER
	say "Veranda $VER ($TAG, $SHORT) to $ORG_URL, tag $VTAG$([ "$DRY" = 1 ] && echo ' [DRY RUN: nothing pushed]')"
fi
W=$DIST/publish/$VER
rm -rf "$W"
mkdir -p "$W/export" "$W/msg"
exec > >(tee "$W/publish.log") 2>&1
NOTES=$W/notes.txt
if [ "$TEST" = 1 ]; then
	: > "$NOTES"
else
	$PY tools/publish.py notes "$TAG" -o "$NOTES"
	$PY tools/publish.py builtfrom "$TAG" > "$W/builtfrom.txt"
	say "the notes ($TAG):"
	sed 's/^/    /' "$NOTES"
fi

# the source commit of a repository: $1 key, $2 tree, $3 refs (comma separated)
source_of() {
	local key=$1 tree=$2 refs=$3 h r
	if [ "$tree" = . ]; then
		echo "$SRC"
		return
	fi
	if [ "$TEST" = 0 ]; then
		h=$(awk -v k="$key" '$1 == k { print $2 }' "$W/builtfrom.txt")
		if [ -n "$h" ]; then
			git -C "$tree" rev-parse --verify -q "$h^{commit}" || die "$key: $h (BUILT FROM) is not in $tree"
			return
		fi
		echo "publish: WARNING: $key is not in $TAG's BUILT FROM: its refs ($refs) instead" >&2
	fi
	for r in ${refs//,/ }; do
		if git -C "$tree" rev-parse --verify -q "$r^{commit}"; then
			return
		fi
	done
	die "$key: none of $refs in $tree"
}

# the organisation's repository $1 cloned into $W/<repo>, on branch $2
clone() {
	local repo=$1 br=$2 c=$W/$1
	if git ls-remote "$ORG_URL/$repo.git" >/dev/null 2>&1; then
		step git clone -q "$ORG_URL/$repo.git" "$c"
	else
		[ "$DRY" = 1 ] || die "$ORG_URL/$repo.git is not there (create it first: docs/PUBLISHING.md, step 2)"
		say "WARNING: $ORG_URL/$repo.git is not there yet (a dry run: a new local repository stands in)"
		git init -q "$c"
		git -C "$c" remote add origin "$ORG_URL/$repo.git"
	fi
	if git -C "$c" rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null; then
		git -C "$c" checkout -q -B "$br" "origin/$br"
	elif [ "$br" = next ] && git -C "$c" rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
		git -C "$c" checkout -q -B next origin/main      # (the first test build: from main)
	else
		git -C "$c" checkout -q --orphan "$br"
	fi
}

# the last source published to the clone's branch (its trailer), or nothing
last_source() {
	git -C "$1" log -1 --format=%B 2>/dev/null | sed -n 's/^Veranda-Source: [^ ]* \([0-9a-f]*\)$/\1/p' | tail -1
}

# the tag v<version> on the clone's HEAD (an existing one must be there already)
tag_it() {
	local c=$1 msg=$2
	[ "$TEST" = 1 ] && return
	if git -C "$c" ls-remote --exit-code --tags origin "refs/tags/$VTAG" >/dev/null 2>&1; then
		die "$(basename "$c"): the tag $VTAG is on GitHub already (a release is published once)"
	fi
	step git -C "$c" tag -a "$VTAG" -F "$msg"
}

publish_export() {     # repo tree key refs branch
	local repo=$1 tree=$2 key=$3 refs=$4 br=$5 src c=$W/$1 e=$W/export/$1 prev msg=$W/msg/$1.txt
	[ "$tree" = . ] || tree=$P/$tree
	[ -e "$tree/.git" ] || die "$repo: no repository at $tree"
	src=$(source_of "$key" "$tree" "$refs")
	say "== $repo: $key at $(git -C "$tree" rev-parse --short "$src") -> $ORG/$repo ($br)"
	clone "$repo" "$br"
	mkdir -p "$e"
	git -C "$tree" archive "$src" | tar -x -C "$e"
	$PY tools/publish.py strip "$e" --repo "$repo" | sed 's/^/  left out (private): /'
	# what tools/publish/ adds
	if [ -d "tools/publish/$repo" ]; then
		cp -r "tools/publish/$repo/." "$e/"
		say "added: $(cd "tools/publish/$repo" && find . -type f | sed 's|^\./||' | tr '\n' ' ')"
	fi
	if [ "$repo" != veranda ]; then
		mkdir -p "$e/.github/workflows"
		$PY tools/publish_ci.py "$repo" > "$e/.github/workflows/veranda-ci.yml"
	fi
	$PY tools/pubscan.py "$e" --repo "$repo" | sed 's/^/  /'
	[ "${PIPESTATUS[0]}" = 0 ] || die "$repo: the export has private files (above)"
	# the clone's tree replaced by the export's
	git -C "$c" rm -rq --cached --ignore-unmatch . >/dev/null
	find "$c" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
	cp -a "$e/." "$c/"
	git -C "$c" add -A
	prev=$(last_source "$c")
	: > "$W/msg/$repo.log"
	if [ -n "$prev" ] && git -C "$tree" rev-parse -q --verify "$prev^{commit}" >/dev/null &&
		git -C "$tree" merge-base --is-ancestor "$prev" "$src"; then
		git -C "$tree" log --reverse --no-merges --format=%s "$prev..$src" > "$W/msg/$repo.log"
	fi
	$PY tools/publish.py msg --version "$VER" --repo "$repo" --key "$key" --source "$(git -C "$tree" rev-parse "$src")" \
		--notes "$NOTES" --log "$W/msg/$repo.log" $([ "$TEST" = 1 ] && echo --test) -o "$msg"
	if git -C "$c" diff --cached --quiet && git -C "$c" rev-parse -q --verify HEAD >/dev/null; then
		say "$repo: the same tree as $br's last commit: no commit"
	else
		step git -C "$c" commit -q -F "$msg"
		git -C "$c" show --stat --format='  %h %s' HEAD | tail -n +1 | sed 's/^/    /' | tail -25
	fi
	tag_it "$c" "$msg"
	push git -C "$c" push origin "refs/heads/$br:refs/heads/$br" ${VTAG:+"refs/tags/$VTAG"}
}

publish_history() {    # repo tree key refs branch
	local repo=$1 tree=$P/$2 key=$3 refs=$4 br=$5 src full prev c=$W/$1 e=$W/export/$1 rm="" msg=$W/msg/$1.txt
	[ -e "$tree/.git" ] || die "$repo: no repository at $tree"
	src=$(source_of "$key" "$tree" "$refs")
	full=$(git -C "$tree" rev-parse "$src")
	say "== $repo: $key at $(git -C "$tree" rev-parse --short "$src") with its history -> $ORG/$repo ($br)"
	clone "$repo" "$br"
	step git -C "$c" fetch -q --no-tags "$tree" "$src"
	mkdir -p "$e"
	git -C "$tree" archive "$src" | tar -x -C "$e"
	rm=$($PY tools/publish.py strip "$e" --repo "$repo")
	[ -z "$rm" ] || echo "$rm" | sed 's/^/  left out (private): /'
	$PY tools/pubscan.py "$e" --repo "$repo" | sed 's/^/  /'
	[ "${PIPESTATUS[0]}" = 0 ] || die "$repo: the tree has private files (above)"
	$PY tools/publish.py msg --version "$VER" --repo "$repo" --key "$key" --source "$full" \
		$([ "$TEST" = 1 ] && echo --test) -o "$msg"
	[ -z "$rm" ] || printf '\nLeft out of the published tree: %s\n' "$(echo $rm)" >> "$msg"
	prev=""
	if git -C "$c" rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null; then
		# published before: the source's new commits merged in (its authors' commits
		# kept), the tree the source's minus the private files; never forced
		prev=$(git -C "$c" log --format=%B "origin/$br" | sed -n 's/^Veranda-Source: [^ ]* \([0-9a-f]*\)$/\1/p' | head -1)
		if [ -z "$prev" ]; then
			git -C "$c" merge-base --is-ancestor "origin/$br" "$src" ||
				die "$repo: $br on GitHub is neither published by this script nor an ancestor of $src"
			git -C "$c" checkout -q -B "$br" "$src"
		elif [ "$prev" = "$full" ]; then
			say "$repo: $br has this source already: no commit"
		else
			git -C "$c" merge-base --is-ancestor "$prev" "$src" ||
				die "$repo: the source published last ($prev) is not an ancestor of $src (never forced)"
			git -C "$c" merge -q --no-ff --no-commit -s ours "$src" >/dev/null 2>&1
			git -C "$c" read-tree -u --reset "$src"
			[ -z "$rm" ] || (cd "$c" && echo "$rm" | tr '\n' '\0' | xargs -0 git rm -q -f --)
			step git -C "$c" commit -q -F "$msg"
			rm=""
		fi
	else
		git -C "$c" checkout -q -B "$br" "$src"
	fi
	if [ -n "$rm" ] && [ "$prev" != "$full" ]; then
		(cd "$c" && echo "$rm" | tr '\n' '\0' | xargs -0 git rm -q -f --)
		step git -C "$c" commit -q -F "$msg"
	fi
	tag_it "$c" "$msg"
	push git -C "$c" push origin "refs/heads/$br:refs/heads/$br" ${VTAG:+"refs/tags/$VTAG"}
}

confirm() {
	[ "$DRY" = 1 ] || [ "$YES" = 1 ] && return
	read -r -p "publish: push $1? Return to go on, Ctrl+C to stop " _ < /dev/tty
}

# ---------------------------------------------------------------- the repositories
$PY tools/publish.py repos > "$W/repos.txt"
LAST=""
while IFS=$'\t' read -r repo tree key refs mode br; do
	want "$repo" || continue
	[ "$TEST" = 1 ] && br=next
	if [ "$repo" = veranda ]; then
		LAST="$repo $tree $key $refs $br"
		continue
	fi
	confirm "$repo"
	if [ "$mode" = history ]; then
		publish_history "$repo" "$tree" "$key" "$refs" "$br" < /dev/null
	else
		publish_export "$repo" "$tree" "$key" "$refs" "$br" < /dev/null
	fi
done < "$W/repos.txt"

# ---------------------------------------------------------------- the site's repository
if [ "$SITE" = 1 ] && [ "$TEST" = 0 ] && want site; then
	repo=$ORG.github.io
	say "== $repo: the website's workflow (the site is built by its action from veranda's tools/site)"
	clone "$repo" main
	c=$W/$repo
	cp -r tools/publish/site/. "$c/"
	git -C "$c" add -A
	if git -C "$c" diff --cached --quiet && git -C "$c" rev-parse -q --verify HEAD >/dev/null; then
		say "$repo: unchanged"
	else
		printf 'Veranda %s: the site'"'"'s workflow\n\nVeranda-Source: Veranda %s\n' "$VER" "$SRC" > "$W/msg/site.txt"
		step git -C "$c" commit -q -F "$W/msg/site.txt"
		confirm "$repo"
		push git -C "$c" push origin refs/heads/main:refs/heads/main
	fi
fi

# ---------------------------------------------------------------- veranda (last: its tag starts the release)
if [ -n "$LAST" ]; then
	set -- $LAST
	confirm veranda
	publish_export "$@" < /dev/null
fi

# ---------------------------------------------------------------- the wiki
if [ "$WIKI" = 1 ] && [ "$TEST" = 0 ] && want wiki; then
	repo=veranda.wiki
	say "== the wiki ($ORG/veranda.wiki.git) from $TAG's docs/manual"
	c=$W/$repo
	if git ls-remote "$ORG_URL/$repo.git" >/dev/null 2>&1; then
		step git clone -q "$ORG_URL/$repo.git" "$c"
	else
		[ "$DRY" = 1 ] || die "$ORG_URL/$repo.git is not there: make the wiki's first page on GitHub (docs/PUBLISHING.md, step 3)"
		say "WARNING: no wiki yet (a dry run: a local repository stands in)"
		git init -q -b master "$c"
		git -C "$c" remote add origin "$ORG_URL/$repo.git"
	fi
	MKWIKI_QUIET=1 "$W/export/veranda/tools/mkwiki.sh" --repo "$ORG/veranda" "$c" | sed 's/^/  /'
	git -C "$c" add -A
	if git -C "$c" diff --cached --quiet && git -C "$c" rev-parse -q --verify HEAD >/dev/null; then
		say "the wiki: unchanged"
	else
		printf 'The Veranda manual, Veranda %s\n\nVeranda-Source: Veranda %s\n' "$VER" "$SRC" > "$W/msg/wiki.txt"
		step git -C "$c" commit -q -F "$W/msg/wiki.txt"
		br=$(git -C "$c" rev-parse --abbrev-ref HEAD)
		confirm "the wiki"
		push git -C "$c" push origin "refs/heads/$br:refs/heads/$br"
	fi
fi

echo
if [ "$DRY" = 1 ]; then
	say "a dry run: nothing pushed. The clones, commits and tags are in $W; the log $W/publish.log"
else
	say "pushed. Next: the release workflow on github.com/$ORG/veranda/actions builds $VTAG's release;"
	say "then check https://$ORG.github.io and https://github.com/$ORG/veranda/wiki (docs/PUBLISHING.md, step 6)"
fi
