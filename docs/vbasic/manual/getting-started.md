# 1. Getting started

VeraBASIC is a BASIC for Veranda on the Commander X16. This chapter gets
a first program running. *VeraBASIC*, the editor, writes, checks and runs
programs on the X16 itself (chapter [5. The editor](editor.md)): start it
from `/VERANDA/APPS` or double-click a `.bas` file, type the program, press
Ctrl+R. *VeraBASIC Run*, the runtime alone, runs a program document (and
a `.bas` file given to it) as it is, and `vbasic.py` is the tool on the PC that
checks programs, runs them and turns them into program documents; any text
editor writes programs too: on the PC, or Veranda Edit on the X16.

## What you need

| Where | What |
|---|---|
| the X16 (or the emulator) | Veranda, and `VeraBASIC.cvt` and `VeraBASIC Run.cvt` in `/VERANDA/APPS`, the help in `/VERANDA/HELP` |
| the PC (optional) | Python 3 and the Veranda SDK's tools: `vbasic.py`, with `vbtokens.py`, `vbtokens_gen.py`, `vbrom.py`, `vpack.py` and `vicon.py` beside it ([the tools](../TOOLS.md)) |

## A first program

Write this into a file called `hello.bas`:

```basic
' hello.bas: a first program
PRINT "Hello from VeraBASIC"
FOR i% = 1 TO 5
  PRINT i%; "squared is"; i% * i%
NEXT
PRINT "Done."
```

A program is plain text, one statement or more a line. Keywords may be
written in any case. A line may start with a number, as in V2 BASIC, but
it need not. `'` starts a comment.

## Running it

Copy `hello.bas` to the card (or write it there with VeraBASIC or Veranda
Edit) and double-click it in the shell: VeraBASIC, the editor, opens it
(chapter 5); Ctrl+R runs it. The runtime reads the text, tokenizes and
prepares it (a few kilobytes take a fraction of a second; it manages more
than 10 KB of source a second), and runs it. Its window is the
**console**: what the program prints appears there, line
by line, and scrolls when the window is full. The status bar says whether
it is running; *Run* > *Stop*, Ctrl+C or the STOP key stops it. When it
ends, the window stays until you press a key, and the editor comes back.

Names may be long: `Bird watch at the feeder.bas` opens like `hello.bas`.
The shell finds VeraBASIC in the folder shown, in `/VERANDA/APPS`, in
`/VERANDA` or in the top folder.

If the program has an error that Run finds before it starts (a `NEXT`
without its `FOR`, a misspelt number), the status bar and a box show the
line and the message, `Line 12: NEXT without FOR` for example, and the
program does not run.

## Checking and building it on the PC

On the PC:

    python3 vbasic.py check hello.bas
    python3 vbasic.py build hello.bas -o hello.cvt

`check` reports the errors it finds as `file:line: message`, so a PC
editor can jump to them; Run reports the same messages. `build` makes the
program document, a GEOS file of class `VeraBASIC V1.0` holding the
program already tokenized and prepared. A double click on it starts
VeraBASIC Run, which tokenizes nothing and runs it at once; its name
may be long too (`-o "Bird watch at the feeder.cvt"`).
*VeraBASIC Run* > *Open program...* in Run's menu opens another
document; it lists the program documents of the current folder by their
16-character GEOS names (the shell's double click is the way to long
names and to `.bas` files).

While a program runs, Veranda goes on working: the menus open, the clock
ticks, and Alt+Tab puts VeraBASIC Run aside with the program in the
middle of what it was doing; brought back from the dock, it goes on from
there. This is because VeraBASIC runs a program in short slices (about
8 ms each) from the main loop rather than taking over the machine.

## Running it on the PC

`vbasic.py run` is VeraBASIC's reference interpreter. It runs the same
program and prints the console's lines to the terminal:

    python3 vbasic.py run --rom rom.bin hello.bas

Floats in VeraBASIC are the X16 ROM's (the same 5-byte format and maths
library as V2 BASIC), so `--rom` names an X16 ROM image: the reference
then runs the ROM's own maths routines and its results are those of the
X16 to the last bit. Without a ROM image it uses the PC's floats, which
differ in the last digits. `--input FILE` gives the keys a program reads
with `INPUT`, a line of the file to a line typed. The gate of this phase
runs every program of its test corpus both ways and compares the logs.

## Typing into a program

`INPUT` waits for a line typed in the console, with a `?` prompt:

```basic
INPUT "Your name"; name$
INPUT "Your age"; age%
PRINT "Hello, "; name$; ". Next year you will be"; age% + 1
```

```keys
Robin
7
```

Backspace takes back a character; Return ends the line. A number that
is not one asks again with `Redo from start`.

## When something goes wrong

An error that the program does not catch stops it. The console shows
the error's number, its message and the line:

```basic
PRINT "before"
x = 10 / 0
PRINT "never printed"
```

prints `Error 11, Division by zero, in line 2`. Under VeraBASIC Run a
box says so as well, and the program ends. The next chapter shows how to
catch errors with `{TRY}` ... `{CATCH}` ... `{END TRY}`.

## Making a program faster

Two habits make most of the difference:

- **Integers.** A name ending in `%` is a 16-bit integer, and arithmetic
  on integers never touches the float routines. `OPTION INTEGER` at the
  top of a program makes every name without a suffix an integer too;
  new programs should start with it. A `FOR` loop over an integer
  counts more than 25,000 times a second.
- **Procedures.** `SUB` and `FUNCTION` with `LOCAL` variables keep a
  program readable at no great cost; `GOSUB` is there for V2 listings.

## Making it an application

When a program is finished, the editor's **File > Make application...**
turns it into an application of its own, with its name and its tile in
`/VERANDA/APPS`: a double click starts it, and nobody needs VeraBASIC to
run it. Its `{APP}` lines give it a name, a tile and the documents it
opens; chapter 7, [Making applications](making-apps.md), has it all.
*File > Save program...* writes a program document instead, which
VeraBASIC Run opens. On the PC, `vbasic.py app` and `vbasic.py build` do
the same.

## The parts and where they come from

| Part | What it is |
|---|---|
| `VeraBASIC Run.cvt` | the runtime: an interpreter in 6502 assembly, about 24 KB with its console window, and the tokenizer in 20 KB of overlays |
| `vbasic.py` | check, build, app, list, import, run (the reference interpreter), doc: [the tools](../TOOLS.md) |
| `docs/vbasic/FORMAT.md` | the token format and the program document |
| [The language](language.md) | the next chapter |
| [The reference](reference.md) | every keyword |
| [The reference card](refcard.md) | the same on two pages |
