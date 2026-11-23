# Publishing Veranda: the veranda-x16 organisation

How Veranda goes public (DECISIONS V139): a GitHub organisation,
[`veranda-x16`](https://github.com/veranda-x16), holds the repositories,
the wiki and the website, `https://veranda-x16.github.io`. GitHub Actions
build every release from the source. You run one command after
`tools/release.sh`: `tools/publish.sh <version>`. Nothing on this machine
pushes or publishes by itself, and no script calls GitHub's API to write.

## The repositories

| Repository | Source here | Licence | Published as |
|---|---|---|---|
| `veranda` | this tree | MIT | one commit a release, minus the private files (below); tag `v<version>`; its workflows build the release |
| `commander-write` | `~/Projects/commander-write` | MIT | one commit a release |
| `commander-calc` | `~/Projects/commander-calc` | MIT | one commit a release (from the `layout` branch, else `veranda`) |
| `lighthouse-pinball` | `~/Projects/veranda-pinball` | MIT | one commit a release |
| `harbour-walls` | `~/Projects/harbour-walls` | MIT | one commit a release |
| `veranda-sidplay` | `~/Projects/veranda-sidplay` | GPL-3.0-or-later (COPYING, NOTICE) | one commit a release |
| `veranda-solitaire` | `~/Projects/veranda-solitaire` | GPL-3.0-or-later, rules from PySolFC (COPYING, NOTICE) | one commit a release |
| `mod-player` | `~/Projects/x16-mod` | MIT; `vendor/micromod-c` is Martin Cameron's micromod, **BSD 3-Clause**, a test oracle only (not compiled into the player) | one commit a release |
| `geochess` | `~/Projects/veranda-geochess` (branch `veranda`) | **no licence file**: Scott Hutter's informal permission in the source ("free to modify ... as long as original author credit is mentioned"); the engine BMCP by Maksim Korzh (WTFPL 2) | **with its history** (Scott Hutter's and the other authors' commits kept), branch `veranda`; best made as a fork of `geos64128/geochess` |
| `x16-emulator` | `~/Projects/x16-emulator-modem` (branch `modem`) | BSD 2-Clause (x16emu's, Michael Steil and the X16 community) | **with its history**, branch `modem`: a fork of X16Community/x16-emulator plus your Zimodem back-end commits; the release workflow builds it to check that Veranda Update installs each release |
| `veranda-x16.github.io` | `tools/publish/site/` | MIT | the website's workflow only; the site is built by it |
| `veranda.wiki` | `docs/manual` | MIT | `tools/mkwiki.sh`; also kept in sync by veranda's wiki workflow |

The map is `tools/publish.repos` (one line a repository: its source, its
refs, its build for CI). The scripts refuse any line naming these, which
are **never** published:

- **geoWrite** (`veranda-geowrite`) and **TopDesk** (`veranda-topdesk`):
  Berkeley Softworks' and GEOS-USER-CLUB's programs, ported for personal use;
- **CommanderSID** (SID Player is its own port, `veranda-sidplay`).

The GitHub release (Veranda Update's files and the SD-card zip) holds
only what `tools/release.allow` names: Veranda, the author's own MIT
programs (Veranda Write, Veranda Calc, MOD Player, Lighthouse Pinball,
Harbour Walls), Solitaire and SID Player (GPL-3.0-or-later, their source
in the organisation) and geoChess (Scott Hutter's, with credit, under the
permission in its source). The port guard of `tools/mkrelease.py` still
refuses geoWrite and TopDesk by name, class and author, even if listed.

### What stays private

`tools/publish.private` lists them; `tools/publish.sh` removes them from
every export and `tools/pubscan.py` refuses an export that still has
one:

| What | Where |
|---|---|
| The decisions log: the requests quoted, the sessions' notes | `docs/DECISIONS.md` (veranda), `DECISIONS.md` (every repository: commander-write has one) |
| The sessions' working notes | `CLAUDE.md`, `MEMORY.md`, `.claude/`, `.mcp.json`, `*.memory.md` anywhere |
| mod-player's plan, decisions, the brief it was built from, this machine's set-up | `PLAN.md`, `docs/decisions.md`, `docs/original-brief.md`, `docs/environment.md` (it has `/home/<you>` paths) |
| Python caches | `__pycache__/`, `*.pyc` (x16-mod tracks one) |
| Keys | `.env`, `*.pem` |
| Memory dumps | commander-calc's `dump*.bin` (untracked today; listed so they never go in) |
| A Windows build of VICE's c1541 (GPL binary, no source) | geochess's `c1541.exe` (removed by one commit on top of its history) |

and pubscan also refuses: an Anthropic, OpenAI, GitHub or AWS key, a
private key block (the gates' made-up key `sk-ant-gate-0000-dummy-...` is
allowed), a home folder written out (`/home/<you>/`), and the names of
your own card files (`tools/tocard.py`'s list, which now lives outside
the tree in `~/Projects/veranda-dist/tocard.keep`).

**Made variables in this change** (they were hard-coded local paths):
`VERANDA_PROJECTS` (the sibling repositories' folder, default
`~/Projects`) in `tools/mkdist.sh`, `release.sh`, `mkx16patch.sh`;
`R49` in `tools/gate.sh`, `gate_bar.sh`, `gate_edit.sh`, `gate_paint.sh`,
`gate_shell.sh`, `gate_mouse.sh`; `EMU_UART` in `gate_net.sh`;
`TOCARD_KEEP` in `tools/tocard.py`; `mkx16patch.sh` no longer falls
back to your e-mail address (it needs `git config user.email`);
`mkrelease.sh` no longer reads
`~/Projects/veranda-x16/.git/config`. Every other `~/Projects` in the
tree is already a variable's default (`EMU`, `EMU_NET`, `EMU_MOUSE`,
`GEOS64_REF`, `DIST`...): pubscan lists them, not fatal.

**Not private but worth a look** (pubscan does not stop them):

- the release notes (`docs/releases/`, the tags' messages) name geoWrite
  and TopDesk ("Commander Write opens geoWrite documents", "the Desktop
  row no longer mentions TopDesk"): names, not programs;
- the history of `sandlbn/veranda-x16`, if you transfer it: its
  `veranda/docs/DECISIONS.md` (up to V88) has been public since then;
- commander-write's `tests/test_main.c` and README read your own
  geoWrite document from `build/` when it is there (by the name
  `tocard.keep` lists): the file is not in the repository, its name is. pubscan stops the export on
  it while `tocard.keep` lists the name: rename the test's file to a
  neutral name in commander-write, or take the name out of `tocard.keep`.

## What `tools/publish.sh` does

    tools/publish.sh --dry-run 1.0    # everything but the pushes
    tools/publish.sh 1.0              # asks before each push (--yes: does not)
    tools/publish.sh --test             # a test build: the branches "next"

For each repository (the siblings first, then the site's repository, then
`veranda`, whose tag starts the release, then the wiki), it prints every
step:

1. clones `https://github.com/veranda-x16/<repo>.git` into
   `~/Projects/veranda-dist/publish/<version>/` (fresh each run);
2. exports the commit the release was built from: `veranda` from the tag
   `veranda-<version>` that `release.sh` made; a sibling from its commit
   in that tag's BUILT FROM; `git archive`, minus the private files, plus
   `tools/publish/<repo>/` (veranda's public `README.md`) and a sibling's
   `.github/workflows/veranda-ci.yml` (from `tools/publish_ci.py`); then
   pubscan;
3. replaces the clone's tree with the export and makes **one commit**
   "Veranda <version>": veranda's body is the release's notes; a
   sibling's, its own commit subjects since the last publish (cleaned of
   V-numbers and "asked for" asides). Every commit ends with
   `Veranda-Source: <key> <hash>`, which the next publish reads. A tree
   that did not change gets no commit, only the tag;
4. tags it `v<version>` (annotated, the same message), and refuses a tag
   the organisation already has;
5. pushes: `git push origin refs/heads/main:refs/heads/main refs/tags/v<version>`,
   with your credentials. Never forced; it never deletes a branch or tag.

`geochess` goes with its history: the first time, the `veranda` branch as
it is plus one commit that removes `c1541.exe`; later, a merge commit
that brings in the new commits (their authors kept). The wiki: the tag's
`docs/manual` through `tools/mkwiki.sh` into `veranda.wiki.git`, one
commit "The Veranda manual, Veranda <version>".

`--test [<ref>]` publishes this tree at `<ref>` (default `main`) and the
siblings at the refs `mkdist.sh` builds to the branches `next`, without a
tag. Not `test`: that is the Test channel's release tag. The push of
veranda's `next` starts its test workflow.

`tests/test_publish.sh` runs all of it against bare repositories in a
folder (`ORG_URL=file://...`, made-up siblings): the dry run pushes
nothing; two releases; the private files and a planted key refused;
geochess merged; `--test`. The ci workflow runs it on every push.

## The workflows

All in the repositories themselves; every action pinned to a commit
(`actions/checkout` v7.0.1, `cache` v6.1.0, `upload-artifact` v7.0.2,
`download-artifact` v8.0.2, `configure-pages` v6.0.0,
`upload-pages-artifact` v5.0.0, `deploy-pages` v5.0.1), `ubuntu-24.04`.

| Repository | Workflow | When | What |
|---|---|---|---|
| veranda | `.github/workflows/release.yml` | a tag `v*` (or by hand, a tag again) | `tools/ci/setup.sh` (cc65 at commit 547d923, built and cached; x16emu R49 and the R49 ROM from the official releases, SHA-256 checked); the siblings cloned at the same tag; `tools/ci/build.sh`: the fast gates, `mkdist.sh`, `mkmanifest.py`, `mkrelease.py --tag v<version>` (the allowlist and the port guard), `mkpubzip.py`, SHA256SUMS; then `gh release create` with GITHUB_TOKEN (UPDATE.LST, the `<crc32>.bin` assets, `veranda-<version>-sdcard.zip`, SHA256SUMS), marked latest; then a `repository_dispatch` to the site if `SITE_DISPATCH_TOKEN` is set |
| veranda | (in release.yml and test.yml) | after the build | **Veranda Update installs the release** (`tools/ci/updcheck.sh`): the x16emu with the Zimodem back-end (`tools/ci/setup.sh modem`: veranda-x16/x16-emulator at commit 97ffc0e), GitHub played on localhost (`tests/update_fake.py`: `latest/download/UPDATE.LST` or `download/test/UPDATE.LST`, each file at `download/<the list's tag>/<asset>`, 302s to another host), a card with no Veranda files, Veranda Update's test build: Check and Update with its default repository; it fails unless every file was fetched, verified by its CRC-32 and put in place, under the list's tag. The release is not made otherwise |
| veranda | `.github/workflows/test.yml` | a push to `next`, by hand, or nightly (skipped when `next` has not moved) | the same build with `--test`, assets replaced on the pre-release `test` (`--clobber`, never latest) |
| veranda | `.github/workflows/wiki.yml` | a push to main touching `docs/manual` | `tools/mkwiki.sh` into the wiki, committed and pushed with GITHUB_TOKEN |
| veranda | `.github/workflows/ci.yml` | every push to main/next, pull requests | the package (this tree only), the host tests (`test_mkrelease.py`, `test_tocard.sh`, `test_publish.sh`), the fast gates |
| each sibling | `.github/workflows/veranda-ci.yml` | pushes, tags, pull requests | Veranda's SDK from `veranda-x16/veranda` (the same tag or branch, else main), then its own build against it |
| veranda-x16.github.io | `.github/workflows/pages.yml` | the dispatch, daily at 04:41 UTC, a push, by hand | `tools/site/build.py --api` from veranda's main, deployed to Pages |

**The fast gates** (`tools/ci/gates.sh`): spec, boot, gfx1, input, disk,
sdk, help, view, shell. They need only the official x16emu and ROM. Run
locally with the official R49 emulator binary and ROM, they pass (with
paint, edit and layout too). The rest need the GEOS 64 reference (gfx,
ui), or the modem, mouse or UART emulator branches (update, gemini,
about...): those stay with `release.sh` on this machine.

**The ROM in CI.** The R49 ROM is downloaded at run time from the
official `X16Community/x16-rom` release (`Release.R49.ROM.Image.zip`;
the official emulator zip carries the same `rom.bin`), checked by its
SHA-256, and never committed, cached in a release, or uploaded as an
artifact (the artifacts exclude `rom.bin`). Its `LICENSE.md`: the
KERNAL and BASIC are Commodore's and Microsoft's code, which "the X16
project has a license to use ... in the context of the X16 computer";
the rest is BSD or public domain. Running X16 software in the X16's own
emulator is that context, and the X16 project itself ships the ROM inside
its emulator downloads; re-publishing the ROM is not allowed, and nothing
here does. It is a reading of the licence, not a grant: if you want
certainty, ask the X16 team.

## First time: your steps, in order

### 1. The organisation

1. github.com > your avatar > **Your organizations** > **New
   organization** > the Free plan. Name: `veranda-x16`. Contact email:
   yours. "My personal account".
2. Settings > **Member privileges**: Base permissions "Read"; leave
   repository creation to owners.
3. Settings > Actions > General: "Allow all actions" is fine (every
   action used is GitHub's own, pinned); **Workflow permissions: Read
   repository contents** (each workflow asks for more itself).

### 2. The repositories

**veranda: transfer sandlbn/veranda-x16 (recommended).** Its stars,
watchers, issues and releases move with it, and GitHub redirects the old
addresses (web and git; release downloads should follow too, so X16s
whose Veranda Update still asks `sandlbn/veranda-x16` keep working: check
it once after the transfer with
`curl -sI https://github.com/sandlbn/veranda-x16/releases/latest/download/UPDATE.LST`,
which should answer 301 to the new name).

1. github.com/sandlbn/veranda-x16 > Settings > General > Danger Zone >
   **Transfer ownership** > "Select one of my organizations":
   `veranda-x16`; type `sandlbn/veranda-x16` to confirm.
2. github.com/veranda-x16/veranda-x16 > Settings > General >
   **Repository name**: `veranda` > Rename. (The redirect follows both
   steps. Never create a new repository called `sandlbn/veranda-x16`
   afterwards: that would end the redirect.)
3. Settings > Branches: keep `main` the default branch. Its other
   branches (term-fix, vera-timer, blank, debuugger, basic-ftp) come
   along; delete them if they are done.
4. `git -C ~/Projects/veranda-x16 remote set-url origin https://github.com/veranda-x16/veranda.git`
   (optional: that clone is no longer used to publish; `release.sh
   --x16` still makes its patch if you want it).

The first `publish.sh` adds one commit on top of its history with the new
layout (this tree at the top instead of `veranda/` and `apps/`).

*Or archive it:* create an empty `veranda-x16/veranda`; in
sandlbn/veranda-x16 edit README.md to one line, "Moved to
https://github.com/veranda-x16/veranda", commit; Settings > Danger Zone
> **Archive this repository**. Then publish one more release there with
the new Veranda Update first, or X16s set to the old repository stop at
its last release (the new Veranda Update reads the old name as the new
one; an older Veranda Update does not).

**The others: new, empty repositories** (New repository > Owner
`veranda-x16`, Public, **no** README, licence or .gitignore):
`commander-write`, `commander-calc`, `lighthouse-pinball`,
`harbour-walls`, `veranda-sidplay`, `veranda-solitaire`, `mod-player`,
`veranda-x16.github.io`. For each one's description: the program's line
from the manual.

**x16-emulator: a fork.** github.com/X16Community/x16-emulator > **Fork** >
Owner `veranda-x16`, name `x16-emulator`. publish.sh adds the branch
`modem` (your Zimodem back-end, 5 commits on its master). The release and
test workflows build it to run Veranda Update against each release.

**geochess: a fork.** github.com/geos64128/geochess > **Fork** > Owner
`veranda-x16`, name `geochess` (copying only the main branch is fine).
publish.sh adds the branch `veranda`. Then in the fork's
About, say it is the Veranda port, and set `veranda` as the default
branch if you want visitors to see it first. Before the first publish,
update `~/Projects/veranda-geochess/NOTICE`: it says "for personal use".

### 3. Pages and the wiki

1. `veranda-x16.github.io` > Settings > **Pages** > Build and deployment
   > Source: **GitHub Actions**. (After the first publish its workflow
   deploys the site.)
2. `veranda` > Settings > General > Features: tick **Wikis**; untick
   "Restrict editing to collaborators only" only if you want public
   edits (the workflow overwrites the manual's pages on each change).
   Open the Wiki tab and **Create the first page** (any text, Save): a
   wiki's git repository exists only after its first page.
3. `veranda` > Settings > **Actions > General > Workflow permissions**:
   "Read and write permissions" is not needed (each workflow asks for
   `contents: write` itself); leave "Read".

### 4. Secrets and tokens

- **None is needed** for the releases, the test channel, the wiki or
  the site: each workflow uses its own `GITHUB_TOKEN`, and the site
  rebuilds every day.
- **Optional, for the site to update within minutes of a release:** a
  fine-grained personal access token. github.com > Settings > Developer
  settings > Fine-grained tokens > Generate: Resource owner
  `veranda-x16`; Repository access "Only select repositories":
  `veranda-x16.github.io`; Permissions: **Contents: Read and write**
  (that is what `repository_dispatch` needs), nothing else; an expiry of
  a year. Then `veranda` > Settings > Secrets and variables > Actions >
  New repository secret: `SITE_DISPATCH_TOKEN`. (The organisation may
  have to allow fine-grained tokens first: org Settings > Personal access
  tokens.)
- Your pushes use your own credentials: `gh auth login` then
  `gh auth setup-git`, or an SSH key (`ORG_URL=git@github.com:veranda-x16`).

### 5. The first publish

    tools/release.sh 1.0                 # as before: gates, package, tag veranda-1.0
    tools/tocard.sh <pkg>                  # the hardware checklist on the X16
    tools/publish.sh --dry-run 1.0       # read it: what goes where, what is left out
    tools/publish.sh 1.0                 # Return before each push

(The first public release is 1.0: `publish.sh 1.0` once `release.sh 1.0`
has made the tag `veranda-1.0`.) Then watch
github.com/veranda-x16/veranda/actions: **release** builds `v1.0`
(about 15 minutes; the first run builds cc65, later ones take it from the
cache). The siblings' **build** workflows run too.

### 6. Check

- https://github.com/veranda-x16/veranda/releases: "Veranda 1.0",
  Latest, with `veranda-1.0-sdcard.zip`, UPDATE.LST, SHA256SUMS and the
  `.bin` assets. Its UPDATE.LST says `tag v1.0` and the build of your
  local package.
- On the X16: Veranda Update > Check (Stable) finds 1.0 (no file to
  fetch if the card already has your package: the same bytes).
- https://veranda-x16.github.io: the release on the home page and under
  Releases (after the dispatch, or the next morning; Actions > pages >
  Run workflow does it at once).
- https://github.com/veranda-x16/veranda/wiki: the manual's pages and
  pictures.
- A test build: `tools/publish.sh --test`, then the pre-release `test`.

## Later releases

`tools/release.sh <version>`, the hardware, `tools/publish.sh <version>`.
To build a published tag's release again: Actions > release > Run
workflow, tag `v<version>` (its assets are replaced). To pull a release:
`gh release delete v<version> --repo veranda-x16/veranda` (the tag
stays); `gh release edit v<older> --latest` makes the one before latest.
