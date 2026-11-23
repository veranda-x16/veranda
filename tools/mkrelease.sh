#!/bin/bash
# Veranda Update's GitHub release (DECISIONS V130).
#
#   tools/mkrelease.sh <pkg-dir> <out-dir>
#
# <pkg-dir>: a package from tools/mkdist.sh (e.g. ~/Projects/veranda-dist/
# pkg-<hash>); <out-dir>: a new folder. Filters the package through the
# allowlist (tools/release.allow: only Veranda and the user's own MIT
# applications; the personal-use ports geoWrite, TopDesk and geoChess are
# refused even if listed), writes the public manifest UPDATE.LST, one asset
# a file (<crc32>.bin) and NOTES.md, and prints the gh command that
# publishes the release. Nothing is pushed or published here: you run that
# command yourself (no GitHub Actions needed).
#
# REPO=owner/repo: the GitHub repository (default veranda-x16/veranda, the
# organisation's: DECISIONS V139; before it, sandlbn/veranda-x16).
# RELEASE_TAG=v1.0: a stable release's tag (the organisation's releases;
# the release workflow passes it); default v<version> (as publish.sh tags the org repos).
set -e
[ -n "$2" ] || { echo "usage: tools/mkrelease.sh <pkg-dir> <out-dir>" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-veranda-x16/veranda}
exec python3 -I -B "$HERE/mkrelease.py" "$1" "$2" --repo "$REPO"
