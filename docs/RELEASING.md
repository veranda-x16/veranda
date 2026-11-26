# Releasing Veranda

How a version of Veranda is built, checked, put on the SD card and
published (DECISIONS V136, V139). One command builds everything, one
more publishes it: `tools/publish.sh <version>` pushes the source to the
GitHub organisation veranda-x16, whose workflow builds the GitHub release
(docs/PUBLISHING.md). The scripts never push, never publish and never
write to a card on their own: publish.sh's pushes are yours, run by you.

| Script | What it does |
|---|---|
| `tools/release.sh <version>` | Runs the gates and builds the package, its README and CHANGES.txt, UPDATE.LST, the zip, the public release folder, the veranda-x16 patch and the local tag. Prints a summary. |
| `tools/tocard.sh <pkg> [<card>]` | Backs up the SD card, copies the package without touching your files, verifies the copy and writes a log. |
| `tools/mkdist.sh <dest>` | The package alone (DECISIONS V71). |
| `tools/mkrelease.sh <pkg> <out>` | The public release folder alone (V130). `CHANNEL=test` makes a test build. |
| `tools/mkx16patch.sh <work> <out>` | The old veranda-x16 patch alone (`release.sh --x16`). |
| `tools/publish.sh <version>` | The organisation's repositories, tags, wiki (docs/PUBLISHING.md). |
| `tools/relnotes.py` | The texts: what's new, the README sections, CHANGES.txt, the tag message. |

## The version

- **`VERSION`** (the top of the tree) holds `N.M` or `N.M.P`. 1.0 is the
  first public version (the packages before it were private builds, some
  of them labelled 0.9.0, never published). Bump `M` for new programs or
  features (1.1) and add `P` for fixes (1.0.1). A test build may carry a
  suffix, `1.0.1-rc1`. Every tool takes both forms: the tags are
  `v1.0` / `veranda-1.0` and `v1.0.1` / `veranda-1.0.1`.
- **The build** is the commit's short hash, plus the date of the build.
- **Where it shows:**
  - The package README's first line reads `VERANDA 1.0 - built <date> (Veranda <hash>)`.
  - UPDATE.LST has a new line, `version 1.0`, right after `build <hash> <date>`.
    A Veranda Update from before this change skips the line, because it
    skips words it does not know. The build id stays the short hash, so
    the backup folders `.SYSTEM/OLD/<build>/` keep their short names.
  - In Veranda Update, Installed and Available read "Veranda 1.0, build
    6d5bf60 of 2026-11-21". A list without a version line shows only the
    build, as before.
  - About this X16's Veranda line reads "1.0, kernel 1.2, API level 6,
    build 6d5bf60". The version is compiled in from `VERSION`
    (`VR_RELEASE`). About is rebuilt for every version, so its line always
    matches the package it came in. The Installed line still shows the
    card's build. The test build has 16 bytes free, so there is no room
    for more.
  - The GitHub release is tagged `v1.0` (before this, the tag was
    `veranda-<date>-<hash>`).
- **The tag** in this tree is `veranda-<version>`, an annotated tag made by
  `release.sh` on the commit it built. The tag message holds the "what's
  new" bullets and the BUILT FROM list (the sibling repositories' commits).
  The next release reads the tag twice: its bullets go into CHANGES.txt,
  and its BUILT FROM decides which checklist sections are NEW. Tags stay
  local until you push them.

## A release, step by step

### 1. Prepare (you)

- Merge everything into `main` and check that `git status` is clean.
- Commit the sibling repositories. Their working trees are never used:
  mkdist builds each one from a committed ref with `git archive`. A dirty
  sibling is only a warning.
- Optionally, write the notes yourself. `tools/release.sh --notes-only 1.0`
  writes a draft into the work folder and prints it. Edit it, commit it as
  `docs/releases/1.0.txt` (one `- ` line per point, in plain words), and
  the release uses it. Without that file, the release uses the generated
  draft: the bold titles of the DECISIONS rows added since the last
  release, plus the commit subjects that no such row covers, with the
  V-numbers and the "(asked for ...)" asides removed.

### 2. `tools/release.sh 1.0` (the script)

1. **Checks.** The version must look like N.M or N.M.P. The tree must be clean.
   You must be on `main`; `--dry-run` allows any branch. The tag must not
   exist yet. It finds the release before: the newest `veranda-*` tag, or,
   before the first tag, the newest `~/Projects/veranda-dist/pkg-*` whose
   build this branch contains (7b07106). `PREV=<commit>` overrides it.
2. **The version.** If `VERSION` differs, the script writes it and commits
   "Veranda 1.0". With `--dry-run` it commits nothing and passes
   `VERANDA_VERSION` to the build instead.
3. **The gates.** It runs every gate: `tools/gate.sh` spec, boot, gfx1,
   gfx, input, ui and disk, then every `tools/gate_*.sh`, one after
   another. Each log goes to `work-<version>-<hash>/gates/`. A gate that
   fails runs once more. If it passes the second time it is listed as
   **FLAKY** in the summary, and the release goes on. If it fails twice,
   the release stops. `--gates "about update"` runs only those gates.
   `--no-gates` (dry runs only) skips them. `--keep-going` (dry runs only) goes on past a failing gate, to try the rest of the pipeline.
4. **The package.** It runs `tools/mkdist.sh` into
   `~/Projects/veranda-dist/pkg-<version>-<hash>`. This includes the three
   programs that used to be copied by hand:

   | Program | Source | Ref |
   |---|---|---|
   | Lighthouse Pinball | `~/Projects/veranda-pinball` (MIT) | `master`, `make -C veranda` |
   | Harbour Walls | `~/Projects/harbour-walls` (MIT) | `master`, `make` |
   | SID Player | `~/Projects/veranda-sidplay` (GPL-3.0-or-later, ported from CommanderSID; CommanderSID itself is never read) | `main`, `make build/app/app.cvt` |

   **TILEHW** (the VERA tile test) has no source in any repository. It is
   carried over from `~/Projects/veranda-dist/tiletrial/TILEHW` (the same
   bytes as every package since 970cb50). `TILEHW=<dir>` points
   elsewhere, and `TILEHW=` leaves it out.
5. **The texts.** `tools/relnotes.py` appends three sections to
   `VERANDA/README.txt`:
   - NEW IN THIS BUILD.
   - The tile test.
   - THE HARDWARE CHECKLIST FOR <version>, built from `tools/checklist.txt`:
     one section per program, each listing its sources. A section is NEW
     when its sources changed since the release before: a tree path
     changed in `git diff`, or a sibling repository was built from another
     commit. NEW sections come first.

   It also writes `VERANDA/CHANGES.txt`: this version, every older
   version from its tag, and `docs/releases/before-1.0.txt` (the builds
   of 2026-11-18 to 2026-11-21). The old "EARLIER" sections no longer pile
   up in the README.
6. **UPDATE.LST** is written again, because the README changed and
   CHANGES.txt is new. It carries the version and up to eight lines of
   what's new.
7. **The zip** goes to `~/Projects/veranda-dist/veranda-<version>-<date>-<hash>.zip`.
   It is personal, because it holds the ports: never share it.
8. **The public release folder.** `tools/mkrelease.sh` writes
   `~/Projects/veranda-dist/rel-<version>-<hash>/`. Only the files named in
   `tools/release.allow` go in, and the port guard refuses geoWrite and
   TopDesk by name, class or author even if listed (geoChess, Solitaire,
   MOD Player, SID Player and the games are listed, with their credits). The script prints the `gh release create` command.
9. **The veranda-x16 patch** (only with `--x16` since V139: the old
   public repository, before the organisation). `tools/mkx16patch.sh` clones
   `~/Projects/veranda-x16` and applies the patches of
   `~/Projects/veranda-dist/patches/veranda-x16/` that its history lacks
   (matched by subject). Then it brings in this tree's changes since the
   commit the last patch was made from. That commit is the newest
   `Veranda-Source:` trailer in the clone's history. Patches made before
   this tooling (up to 0021) have no trailer, so the script falls back to
   9277017 (`X16_BASE=` overrides it).
   - **Left out:** `docs/DECISIONS.md`, `README.md` and `docs/releases/`.
   - **Files veranda-x16 never changed:** taken whole.
   - **`tools/mkdist.sh`:** taken whole. It is now the same file in both
     trees, because it builds veranda-x16's `../apps/*` itself (MONO).
   - **Files both sides changed:** merged three ways with
     `git merge-file`. A conflict stops the script and nothing is made.

   The script then:
   - derives the top-level Makefile's `VAPPS` from the `app apps/<dir>`
     lines in mkdist.sh;
   - lists any new program that README.md does not name;
   - compares veranda-x16's `apps/*` with the sibling repositories;
   - commits and writes `NNNN-Veranda-<version>-....patch` (with
     `--binary`);
   - runs `make build` and `make dist` in the clone and refuses a port in
     `dist/`;
   - runs gates about and update in the clone (`X16_GATES`).

   `~/Projects/veranda-x16` itself is never written.
10. **The tag.** It creates `veranda-<version>` (annotated, local).
11. **The summary.** It prints the version, the gate results, the paths and
    sizes, and your remaining steps. All of it also goes to
    `release-<version>-<hash>.log`.

### 3. The card (you start it): `tools/tocard.sh <pkg> [<card>]`

The card argument defaults to the one card under `/run/media/$USER` that
has a VERANDA folder.

1. **The plan.** It **refuses**, writing nothing and exiting with code 3,
   if the package would overwrite a file that looks like yours:
   - anything in `VERANDA/.SYSTEM`;
   - a name you keep: `TOCARD_KEEP=a.cvt,b.pdf`, else the names in
     `~/Projects/veranda-dist/tocard.keep` (one a line; outside the tree,
     since the names of your own files are your own);
   - a file whose size or CRC-32 no longer matches the card's
     `VERANDA/UPDATE.LST`, meaning it changed on the card after the
     install (README.txt, CHANGES.txt and UPDATE.LST are exempt);
   - a file not in that list that was written more than an hour after the
     card's `VERANDA.SYS`.

   `--force` overwrites them, after the backup. A file already in
   `/DOCUMENTS` is never written. `--dry-run` stops after the plan.
2. **The backup.** It copies the card's VERANDA, DOCUMENTS, PC and TILEHW
   folders to `~/Projects/veranda-dist/card-backup-<date>` (then `b`, `c`
   and so on), and compares the copy with `diff -r`.
3. **Dropped files.** Files an earlier package installed that this one no
   longer has (TopDesk.cvt after 6d5bf60) are moved to
   `/VERANDA/.SYSTEM/OLD/`, renamed `name~2` if the name is taken. Only
   files still exactly as installed are moved. Nothing is deleted.
4. **The copy.** It runs `rsync -rt --checksum` (with no `--delete`), then
   `sync`. `--checksum` matters: VERANDA.PRG often keeps its size, and
   rsync's quick check would skip a file of the same size and a close
   date. Its test caught exactly that.
5. **The check.** Every package file is compared byte for byte, every
   moved file must be whole, and every other file of the four folders must
   be unchanged (SHA-256 before and after). The log is
   `card-backup-*/tocard.log`, next to the plan's lists.

The test for this script is `tests/test_tocard.sh` (run by gate update).
It uses a made-up card folder and never a real card.

### 4. Publish (you)

1. **Try it on the X16.** Work through the README's HARDWARE CHECKLIST,
   NEW items first.
2. **The organisation** (docs/PUBLISHING.md):
   ```
   tools/publish.sh --dry-run 1.0
   tools/publish.sh 1.0
   ```
   Each repository of veranda-x16 gets one commit "Veranda 1.0" and the
   tag `v1.0`; the wiki its pages. The tag starts veranda's release
   workflow, which builds the GitHub release from the source (the
   allowlist and the port guard as here, plus the SD-card zip). Its
   `UPDATE.LST` carries your package's build id, so a card with your
   package finds nothing to fetch.
3. **This tree:** `git push origin main veranda-1.0`, if you keep a
   remote.
4. **The private download page** (the artifact) is not scripted: upload the
   zip by hand, as before.

## The channels: Stable and Test

Veranda Update has a channel setting. Source... asks "Stable releases?";
Cancel means Test. The setting is stored in `/VERANDA/.SYSTEM/UPDATE.CFG`
as `channel=stable` or `channel=test`.

| Channel | Address | Made by |
|---|---|---|
| Stable | `https://github.com/<repo>/releases/latest/download/UPDATE.LST` | the release workflow on the tag `v<version>` (`tools/publish.sh`; V139), `--latest`; before it `release.sh` / `mkrelease.sh` with the tag `veranda-<version>` |
| Test | `https://github.com/<repo>/releases/download/test/UPDATE.LST` | the test workflow on the branch `next` (`tools/publish.sh --test`, by hand, nightly): the one release tagged `test`, a pre-release, `--latest=false`, its assets replaced (`--clobber`); by hand: `CHANNEL=test tools/mkrelease.sh <pkg> <out>` |
| A PC | `http://<pc>:8644/UPDATE.LST` | `python3 PC/update_server.py <pkg>`: your own builds, ports included, LAN only |

**Why a fixed `test` tag, and not the API's list of releases?** The other
way would be `api.github.com/repos/<repo>/releases?per_page=1`, which
includes pre-releases, against `/releases/latest`.

- **JSON on the X16.** That API answers in JSON: an array of releases, each
  with every asset's name, URL, uploader and dates. That is tens of KB
  for a release of 60 assets, and the tag Veranda Update needs is inside
  it. It would need a streaming JSON scanner in Veranda Update, whose main
  RAM has about 3 KB free and whose overlays have 1.8-2.4 KB.
- **Another host.** The API needs a second host (api.github.com) and a
  `User-Agent`. Unauthenticated calls are limited to 60 an hour.
- **Ordering.** The API's ordering is by creation date, not by version.

A fixed tag uses the same path scheme as Stable, the same 302 to the asset
host, and the same code: one string differs (`job.c`'s `url_of`, about 30
bytes). Replacing the assets is safe while an X16 is half way through an
update. The assets are named by their CRC-32, so the old ones stay in the
release: an X16 still holding the previous list finds every file it names.
The cost: the `test` release collects old assets over time. Delete them
with `gh release delete-asset test <asset>`, or delete and recreate the
release, at a moment when no one is updating.

The release `test` is not created until you publish a test build. Until
then, Test's Check says "the repository has no release with UPDATE.LST".

## Rolling back

- **A bad release on GitHub:**
  `gh release delete v1.0 --repo veranda-x16/veranda --cleanup-tag`. The X16s
  then see the previous `--latest` release. To make an older one latest
  again, use `gh release edit v<older> --latest`. An X16 that already
  updated can use **Undo last update**, which restores the files from
  `/VERANDA/.SYSTEM/OLD/<build>/`.
- **A bad card:** restore the backup that tocard made:
  ```
  rsync -rt --checksum ~/Projects/veranda-dist/card-backup-<date>/ <card>/
  ```
  Then delete the files the new package added (the `copy.lst` in that
  backup lists them). Files moved to `/VERANDA/.SYSTEM/OLD/` can be moved
  back by hand.
- **The public repository** (before the push):
  `git -C ~/Projects/veranda-x16 reset --hard HEAD~1`. After the push,
  revert the patch's commit with `git revert`.
- **The tag in this tree:** `git tag -d veranda-1.0`. The VERSION commit
  can stay, and the next release reuses or bumps it.
- **A release.sh run that stopped:** nothing was published. Delete its
  `work-*`, `pkg-*`, `rel-*` and zip, fix the cause, and run it again. The
  script refuses to overwrite any of them.

## What stays manual

- Writing good notes, when the generated draft is too technical
  (`docs/releases/<version>.txt`).
- The hardware checklist on the X16.
- Running `tools/publish.sh` (its pushes are yours). The GitHub release
  itself is the release workflow's (`gh release create` by hand only for
  the old repository, `--x16`).
- The private download page.
- Veranda Write's dictionaries (V198): not in a Veranda release. Their
  own release, `dict-1` of veranda-write, is made once (and again only
  when the dictionaries change): Actions > Dictionaries > Run workflow
  there, or `make dict-release` in commander-write and the `gh` command
  it prints.
- TILEHW, which has no source: it is carried over.
