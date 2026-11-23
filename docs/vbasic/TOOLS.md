# VeraBASIC: the tools

The PC side of VeraBASIC (docs/DECISIONS.md V85-V87): the tool that
checks, builds and runs programs, the generator behind the keyword table,
and the helpers the gates use. Every tool is Python 3 only and is run
with `-I` as Veranda's other tools are. The token format, the program
document and the guarantees G1-G4 are in [FORMAT.md](FORMAT.md); the
language is in the [manual](manual/README.md).

| Tool | What it does | Who uses it |
|---|---|---|
| `tools/vbasic.py` | check, build, list, canonical form, the reference interpreter | programmers, every VeraBASIC gate |
| `tools/vbtokens.py` | the PC tokenizer, prepare, detokenizer, the program document (vbasic.py imports it) | vbasic.py, gates `vb_spec`, `vb_tok` |
| `tools/vbtokens_gen.py` | the tables vbtokens.py reads (generated) | vbtokens.py |
| `tools/vbrom.py` | the X16 ROM's maths routines in a small 65C02 emulator, for `run` | vbasic.py |
| `tools/vbgen.py` | the generator: everything that comes from `vbasic/keywords.tbl` | maintainers, gate `vb_spec` |
| `tools/vbfuzz.py` | random valid programs from a seed | gates `vb_spec`, `vb_tok` |
| `tools/vbapp.py` | `vbasic.py app`: a program and VeraBASIC Run made into an application (DECISIONS V99) | vbasic.py, mkdist, gate `vb_app` |
| `tools/vbimport.py` | `vbasic.py import`: a Commodore BASIC V2 `.PRG` as source | vbasic.py, gate `vb_app` |
| `tools/vbmanual.py` | `vbasic.py doc`: the manual as HTML and PDF, the reference card's PDF (the standard library only) | vbasic.py, mkdist, gate `vb_app` |

On the X16, *VeraBASIC Run* holds the same tokenizer and prepare in 6502
assembly (overlays 2-5): it opens a `.bas` file as well as a program
document, and gate `vb_tok` checks that both tokenizers give the same
bytes (G3).

## 1. vbasic.py

    python3 -I vbasic.py check FILE.bas...
    python3 -I vbasic.py build FILE.bas -o OUT.cvt
    python3 -I vbasic.py app FILE.bas [-o OUT.cvt] [--run RUN.cvt]
    python3 -I vbasic.py list FILE.cvt
    python3 -I vbasic.py import FILE.PRG [-o OUT.bas]
    python3 -I vbasic.py doc OUTDIR
    python3 -I vbasic.py canon FILE.bas [-o OUT.bas]
    python3 -I vbasic.py dump FILE.bas
    python3 -I vbasic.py run FILE.bas|FILE.cvt [--rom ROM] [--input KEYS] [--log] [--trace] [--replay LOG] [--dir DIR]

It needs `vbtokens.py`, `vbtokens_gen.py` and `vbrom.py` beside it, and
for `build` the SDK's `vpack.py` and `vicon.py`. The exit status is 0
when all went well, 1 on an error in the program, 2 on a wrong command
line.

### check

Tokenizes and prepares each file and prints every error it finds, one a
line, as `file:line: message`, the form PC editors jump to:

    hello.bas:12: NEXT without FOR
    hello.bas:20: END IF missing for IF in line 4

The messages are those of [FORMAT.md](FORMAT.md) section 5.4 and the
tokenizer's own (*Unexpected character*, *Name too long*, *Number too
big* ...). VeraBASIC Run reports the same message for the first error
when it opens a `.bas` file (as `Line 12: NEXT without FOR`).

### build

Makes the **program document**: a GEOS VLIR file in CVT format, type
`APPL_DATA`, class `VeraBASIC   V1.0` and parent class `VBRun       V1.0`
(VeraBASIC Run), holding the four records of the prepared program. The
output's name may be long (up to 63 characters and `.cvt`, DECISIONS
V82): `vbasic.py build birds.bas -o "Bird Watch from the lake.cvt"`. The
GEOS name inside the file is its first 16 characters; Veranda uses the
whole FAT name.

A double click on the document in Veranda's shell starts VeraBASIC Run
with it: the shell reads the document's parent class and looks for an
application of that class in the folder shown, in `/VERANDA/APPS`, in
`/VERANDA` and in the top folder (DECISIONS V87). A `.bas` file opens
in VeraBASIC, the editor, which declares `documents = BAS` (V48, V93;
Run declared it until V93), so `build` is for finished programs: it saves
the tokenizing at each start, and a document cannot be edited by mistake.

### app

Makes a **standalone application** (DECISIONS V99), what the editor's
*File > Make application...* makes, byte for byte but the date in the
file's directory entry (bytes 23-27; gate `vb_app` compares the two):
VeraBASIC Run's file (`--run`, else `$VB_RUN`, else `VeraBASIC Run.cvt`
in the current folder) with the program's four records after Run's
twelve, its info block and tile from the program's `APP` lines
([FORMAT.md](FORMAT.md) section 7.3; the manual's chapter 7). The output
defaults to `<APP NAME>.cvt`; an error in an `APP` line is reported as
`file:line: message`.

### import

A tokenized Commodore BASIC V2 program (a `.PRG` as the C64 or the X16's
BASIC saves it) as VeraBASIC text: each keyword token its word with
blanks round it (a crunched `FORI=1TO9` becomes `FOR I=1 TO 9`), text in
quotes, after `REM` and in `DATA` as it was, PETSCII to Latin-1 (a
control character in quotes as `" + CHR$(n) + "`); an X16 BASIC
statement (`$CE` and a byte) is kept as a comment, with a warning on
standard error. The manual's chapter 8.

### doc

The manual (`tools/vbmanual.py`): `OUTDIR/html/` (a page a chapter,
`index.html` the contents), `OUTDIR/VeraBASIC-manual.pdf` (the chapters
of `vbmanual.CHAPTERS`, the contents with page numbers, bookmarks) and
`OUTDIR/VeraBASIC-reference-card.pdf` (`refcard.md` on two A4 pages);
then it checks them (the PDFs' cross-reference tables, the card's two
pages, the HTML's links). The PDF writer is its own, with the standard
fonts: no library beyond Python's.

### list

The source of a program document, or of the program inside a made
application, in canonical form: the way back when the `.bas` file is
lost.

### canon

The canonical form of a source (`detok(tok(S))`, [FORMAT.md](FORMAT.md)
section 6): keywords in upper case, one blank between words, two blanks
an indentation level, literals as spelled. Running it twice gives the
same text (G2), and the canonical form runs as the source does (G4).

### dump

The four records in hex, the symbol table (names, types, kinds, targets)
and the procedures with their frames: the tokenizer's view of a program.

### run

The **reference interpreter**: the language, run on the prepared token
form as VeraBASIC Run runs it. The console's lines go to standard
output. The Veranda statements (phase 3, `tools/vbveranda.py`) are
parsed, checked and logged as Run's test build logs them, but not drawn:
`VB> @nn args` for a statement (its second-page byte, its arguments as
Run converts them), `VB= @nn value` for a function, `VB EVENT d KIND ...`
for a handler started at the program's d-th event point.

| Option | |
|---|---|
| `--rom ROM` | an X16 ROM image (`rom.bin`); floats are then computed by the ROM's own maths routines (`vbrom.py`), the X16's to the last bit. `$VB_ROM` does the same. Without one the PC's floats are used and marked approximate |
| `--input KEYS` | a file of the keys typed: a line of it is a line typed, for `INPUT` and `LINE INPUT` |
| `--log` | the runtime's test-log form: `VB| line` for each console line, then `VB END`, `VB ERROR n` or `VB INPUT` (it waited for keys it did not get) |
| `--trace` | `TRON`'s trace without `--log` too: `VB TRON n` for each line entered while it is on (its number, or its line in the text), among the console's lines; the editor's trace pane holds the last 200 of them (DECISIONS V97, gate `vb_debug`) |
| `--replay LOG` | VeraBASIC Run's log of the same program: what only the machine knows comes from it (the functions' values: the pointer, the keys, the fonts' widths, the clock; the events, each at the event point where Run took it); everything else must then log the same, line for line. Without it the functions are 0 and a program waiting for events ends with `VB STUCK`. Part 2 (V90): the dialog boxes' answers (`VB= @nn ...`, a `DIALOG`'s fields and result), the folder the Open and Save dialog chose (`VB CD path`), the clipboard's text and `DIR$`'s names come from it too; a string's control characters, `\` and bytes from 127 on are logged as `\` and two hex digits |
| `--dir DIR` | the folder that stands for the card's top folder: the program's files are made, read, renamed and removed there for real (part 2, `tools/vbveranda2.py`), so a gate compares the folder Run left with the reference's, file for file; the current folder by default |

Gate `vb_core` compares this log with VeraBASIC Run's for every program
of `tests/vbasic/core` and the manual's listings; gate `vb_tok` does it
again with Run tokenizing the `.bas` files itself.

## 2. vbtokens.py

The tokenizer under vbasic.py, usable alone:

    python3 -I vbtokens.py check FILE.bas...
    python3 -I vbtokens.py canon FILE.bas [-o OUT]
    python3 -I vbtokens.py tok FILE.bas -o OUT.cvt
    python3 -I vbtokens.py list FILE.cvt
    python3 -I vbtokens.py dump FILE.bas

`tok` is `vbasic.py build`. In Python: `check_text(text)` gives a
`Program` (its `errors` as `(line, message)`), `encode(prog)` its four
records, `write_document(name, records)` the CVT file,
`read_document(data)` a program back, `detok(prog)` the canonical text,
`float5(text)` a float spelling's 5 bytes (correctly rounded, which
VeraBASIC Run's overlay 5 reproduces with big integers).

## 3. vbgen.py and the keyword table

`vbasic/keywords.tbl` is the single source for every keyword: its token
number, kind, argument signature, the overlay that runs it, the kernel
calls it maps to, its syntax line, help text, example and "see also".
The head of the file describes the line format; in short:

    kw NAME | TOKEN | KIND | ARGS | OVERLAY | KERNEL | GROUP [| FLAGS]
      syntax: ...
      help: ...
      example: ...
      see: ...
    const NAME | VALUE | GROUP [| api=NAME | theme=NAME]
    apiconst PREFIX | GROUP
    retired TOKEN | NAME

    python3 -I tools/vbgen.py [--tbl FILE] [--api FILE] [--out DIR] [--check-only]

writes, at the paths the repository holds:

| File | Contents |
|---|---|
| `vbasic/gen/tokens.inc` | ca65: the tags, `TK_*`/`TX_*`, `VBC_*`, the flag bits; with `VB_LEXTABLES` the X16 lexer's tables (the keywords by length, compounds, flags, procedure arguments: overlay 2), with `VB_TABLES` all of them (dispatch, values, names); the macros `vb_entries_X` (each overlay's entries) and `vb_consts_table` (the predefined constants, overlay 4) |
| `tools/vbtokens_gen.py` | the same tables for Python |
| `vbasic/gen/HELP/KEYWORDS.HLP` | the editor's help pages: every keyword and constant, the groups, Contents and Index |
| `vbasic/gen/HELP/ERRORS.HLP` | the run-time errors' pages (`vbasic.py`'s `ERRORS` and what each means), the Check messages |
| `vbasic/gen/HELP/TUTORIAL.HLP`, `EDITOR.HLP` | the manual's `tutorial.md` and `editor.md` as help pages (headings start pages, `{KEYWORD}` a link, listings indented) |
| `vbasic/gen/idekw.h` | the editor's tables (C): the keywords' words (its colouring), their syntax lines (its status bar), the tokens' names and classes (its Format) |
| `docs/vbasic/manual/reference.md`, `tokens.md`, `refcard.md` | the manual's reference, token list and card |

It fails, listing every problem, when a keyword lacks its syntax, help or
example, on a duplicate or retired token, an unknown kind, flag or
argument code, a kernel name neither in `api/veranda.api` nor in the
SDK's headers, a constant whose value differs from the API's, and a
`{KEYWORD}` in a hand-written chapter that the table does not have.

**Adding a keyword:** give it the next free token of its page (the free
numbers are in `tokens.md`), write its lines with an example, run
`vbgen.py`, and commit the generated files with the table: gate `vb_spec`
fails when they differ from what the generator makes. A token number,
once released, is never given to another keyword; a keyword that goes
stays as a `retired` line. A new keyword also needs its code in the
runtime (`vb_entries_X` names the routine) and, when it changes how a
line is tokenized (a new flag), the same change in `vbtokens.py` and in
VeraBASIC Run's lexer (`apps/vbasic/vbtok.s`): gate `vb_tok` catches a
difference byte for byte.

## 4. vbfuzz.py

    python3 -I vbfuzz.py SEED [-o FILE]

A random program from the seed alone (the same seed, the same bytes):
structured or line-numbered, every block closed, names that are neither
keywords nor constants, keywords in random case and blanks at random, so
its canonical form differs from it. Gates `vb_spec` (G1, G2) and
`vb_tok` (G3) run hundreds of them.

## 5. The gates and their helpers

| Gate | Checks | Helpers (`tests/vbasic/`) |
|---|---|---|
| `tools/gate_vb_spec.sh` | the generator, `tokens.inc`, G1 and G2, the planted errors | `check_vb_spec.py`, `check_tokens_inc.py`, `corpus/`, `errors/` |
| `tools/gate_vb_core.sh` | VeraBASIC Run against the reference (G4), Ctrl+C, the switcher | `check_core.py`, `mkcore.py`, `doclistings.py`, `core/`, `special/` |
| `tools/gate_vb_speed.sh` | the plan's speed table, BM1-BM8 against the ROM's BASIC; the targets met are checks (DECISIONS V107), the others reported | `speed_report.py`, `speed/` |
| `tools/gate_vb_tok.sh` | G3 on 893 programs, the tokenizer's speed, the core programs run from `.bas`, the shell's double clicks, long names | `mktokset.py`, `check_tok.py`, `vb_shell_script.py`, `shell/` |
| `tools/gate_vb_ui.sh` | the Veranda extensions part 1: 19 programs (12 examples, the tutorial's 7 steps) played with the mouse and the keys, logs against `run --replay`, the events, the screens' goldens, put aside mid-loop, a menu while BASIC runs, the extensions chapter's listings | `ui_mouse.py` (`NAME.ms` to an x16emu `-mousescript`), `check_ui.py` (goldens), `ui/` |
| `tools/gate_vb_files.sh` | the Veranda extensions part 2: files (63-character names), folders, the kernel's errors under `TRY`, `DIR$`, the dialog boxes and the Open and Save dialog played with the mouse, pictures, icons, sprites, tiles, the clipboard, the four example programs, the chapter's listings; each session's log against `run --replay --dir`, the folder Run left against the reference's, the Text Scrap as Veranda Edit writes it, the Photo Scrap; on the host folder and an SD card image; screenshots | `vb_session.sh` (a session), `vb_compare.sh` (log and folder), `vb_log.py` (the log out of the console: the DOS commands the emulator echoes), `check_files.py`, `ui_mouse.py` (`dialog N`), `files/` |
| `tools/gate_vb_sdk.sh` | `vr_tile` in the SDK (`veranda.lib`, `vr.h`, `src/vrtile.c`), the shell compiling it into its tiles' overlay; gates `sdk`, `shell`, `edit` | |

`mktokset.py DIR [--fuzz N] [--big]` writes the programs G3 is checked
on (the corpus, the planted errors, the core programs, the manual's
listings, every keyword's example, N fuzz programs, float spellings, a
55 KB program). VeraBASIC Run's test build tokenizes each (`!tok NAME`
in its `VBTEST.LST`) and prints the records in hex; `check_tok.py` then
compares them with `vbtokens.py`'s, and the first error's message for a
program with one, and reports the speed from the emulator's cycle
counter.
