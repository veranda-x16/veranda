# 7. Making applications

A finished program can become a Veranda application of its own: a file
in `/VERANDA/APPS` with its own name, its own tile in the shell and the
dock, the documents it opens with a double click, and nothing else to
install. The editor's **File > Make application...** makes it; on the
PC, `vbasic.py app` makes the same file, byte for byte (apart from the
date in the file's directory entry).

## What an application is

An application made by VeraBASIC is *VeraBASIC Run* with the program
inside it. Its file holds Run's own records (the runtime, about 88 KB on
the card) and after them the program's four records, the same ones a
program document holds (docs/vbasic/FORMAT.md, section 7.3). Its info
block (the class, the author, the description, the extensions it opens)
and its tile come from the program's `{APP}` lines. When it starts it
finds the program in its own records and runs it at once: there is no
*Open program...* in its first menu, the menu is named after the
application, and its window is titled with its name.

| | A `.bas` file | A program document | An application |
|---|---|---|---|
| made by | you, the editor | *File > Save program...*, `vbasic.py build` | *File > Make application...*, `vbasic.py app` |
| opens with | VeraBASIC (the editor) | VeraBASIC Run | itself |
| needs | VeraBASIC | VeraBASIC Run on the card | nothing |
| its tile | the shell's for text | VeraBASIC's icon | its own (`{APP}` `{TILE}`) |
| size | the text | the tokens | the tokens and the runtime, about 90 KB |

The application carries the version of the token format it was made
with; a VeraBASIC Run older than the program says *Made by a newer
VeraBASIC* rather than run it wrongly.

## The APP lines

`{APP}` lines describe the application. They do nothing when the program
runs (from the editor or VeraBASIC Run), so they can stay at the top of
the program while you work on it:

```basic
APP NAME "Bird Watch", CLASS "BirdWatch", VERSION "1.0", AUTHOR "Me"
APP DESCRIPTION "Counts the birds at the feeder."
APP DOCUMENTS "BRD"
APP TILE SKY
PRINT "The APP lines do nothing when the program runs."
```

| Item | What it gives | Default |
|---|---|---|
| `NAME n$` | the application's name: its file (`n$.cvt`, up to 63 characters, none of `/ : * ? = "`), its first menu, its window's title, `DOCUMENT$`'s owner | the `.bas` file's name |
| `CLASS c$` | its GEOS class (12 characters), which its own GEOS documents name as their parent | the name's first 12 characters |
| `VERSION v$` | the class's version, `"1.0"` style (6 characters) | `"1.0"` |
| `AUTHOR a$` | 19 characters, shown by the shell's *Info* | none |
| `DESCRIPTION d$` | 95 characters, shown by the shell's *Info* | none |
| `DOCUMENTS e$, ...` | up to four file extensions of 1-4 letters or digits: a double click on such a file starts the application with it (V48) | none |
| `TILE colour` | the tile's paper: a colour of Look 2 (`SKY`, `ORANGE`, `DUSK` ...) | VeraBASIC Run's (green) |
| `STAY` | the switcher never puts it aside: Alt+Tab asks to quit it instead | off |
| `CLASSIC` | the first menu is not named after the program | off |

Items go on one line or several, separated by commas. The values must be
written out: a string in quotes, a colour by its name or number. The
editor reads the lines from the text itself, so a value worked out by an
expression is an error, *APP: NAME "...", CLASS "...", TILE SKY ...*.

## The tile

The shell shows an application as a tile: a 32 x 32 picture in the ink
on a block of 4 x 4 cards of one paper colour, in a rounded frame the
shell draws. `{APP}` `{TILE}` gives the colour; 32 rows of 32 characters
in `{TILE}` `DATA` lines give the picture, `#` for the ink and `.` for
none. Without them the application has VeraBASIC Run's tile.

```basic
APP TILE ORANGE
TILE DATA "................................", "................................"
TILE DATA "................................", "................................"
TILE DATA "................................", "................................"
TILE DATA "...............##...............", "..............####.............."
TILE DATA ".............######.............", "............########............"
TILE DATA "...........##########...........", "..........############.........."
TILE DATA ".........##############.........", "........################........"
TILE DATA ".......##################.......", "......####################......"
TILE DATA ".....######################.....", "....########################...."
TILE DATA "...##########################...", "..############################.."
TILE DATA ".............######.............", ".............######............."
TILE DATA ".............######.............", ".............######............."
TILE DATA "................................", "................................"
TILE DATA "................................", "................................"
TILE DATA "................................", "................................"
TILE DATA "................................", "................................"
PRINT "The tile is the application's, not the program's."
```

Leave the outermost two pixels empty: the frame is drawn over them. A
tile is easiest to draw in a PC editor with a fixed font; the rows
must be exactly 32 characters, and there must be 32 of them.

## Documents

`{APP}` `{DOCUMENTS}` names the extensions the application opens. A
double click on `Garden.brd` in the shell then starts *Bird Watch* with
that file; the program finds its whole name in `{DOCUMENT$}` and the
current folder is the file's. Started any other way, `{DOCUMENT$}` is
`""`, and under VeraBASIC Run (or the editor) it is always `""`.

```basic
doc$ = DOCUMENT$
IF doc$ = "" THEN
  PRINT "Started without a document"
ELSE
  OPEN #1, doc$, "r"
  LINE INPUT #1, a$
  CLOSE #1
  PRINT "The document says "; a$
END IF
```

Writing such a file is up to the program: `{OPEN}`, `{PRINT}` `#` and
`{CLOSE}`, in `{FOLDER$}`(`DOCS`) for a new one.

## Making it

In the editor, **File > Make application...**:

1. The program is checked, as **Check** does (Ctrl+K); an error stops it
   there, with the line shown red.
2. The `{APP}` lines are read; an error in them is shown with its line.
3. The Save dialog opens in `/VERANDA/APPS` with the application's name.
   Choose another folder if you want it elsewhere; a name without
   `.cvt` gets it. An application of that name already there is replaced
   after a question.
4. VeraBASIC Run's file is read from `/VERANDA/APPS` (or the card's top
   folder) and the application written: the status bar says *Written:
   Bird Watch.cvt*.

The shell shows it with its tile the next time the folder is shown; a
double click starts it, Alt+Tab puts it aside and the dock brings it
back, and its own Quit (a handler that ends with `{END}`) quits it.

**File > Save program...** writes a program document instead (class
`VeraBASIC V1.0`, opened by VeraBASIC Run), as `vbasic.py build` does.

On the PC:

```
python3 -I -B tools/vbasic.py app "Bird Watch.bas" \
    --run "VeraBASIC Run.cvt" -o "Bird Watch.cvt"
python3 -I -B tools/vbasic.py list "Bird Watch.cvt"
```

`--run` names VeraBASIC Run's file (the one on the card, or the SDK's
build); `-o` defaults to the name from `APP NAME`. `list` shows the
program inside an application, as it does a document's.

## Bird Watch, the application

`/DOCUMENTS/VeraBASIC Examples/Bird Watch.bas` is the tutorial's
seventh step with its `{APP}` lines, a tile of a bird on `SKY`, `.brd`
documents (a count of birds, read with `{DOCUMENT$}` at the start and
written by *File > Save the count*, into `/DOCUMENTS/Sightings.brd` when it was started without one) and *File > Put aside* (`{ASIDE}`,
as Alt+Tab). The package ships it made, as `/VERANDA/APPS/Bird
Watch.cvt`, with `Garden.brd` in `/DOCUMENTS` to open with it.

## Memory

An application needs what VeraBASIC Run needs (13 RAM banks at rest)
and one bank for each 8 KB of its program, so a small one runs in about
15 banks and can be put aside at 512 KB. Its program has the same room
for names in main RAM as under VeraBASIC Run.
