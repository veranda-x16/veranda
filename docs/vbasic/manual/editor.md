# 5. The editor

*VeraBASIC* is the editor and the runtime in one program: you write a
program, check it, run it and come back to it without leaving. It opens
`.bas` files: a double click on one in the shell starts it, and File >
Open finds them with their long names. *VeraBASIC Run* stays for finished
programs: the program documents `vbasic.py build` makes.

## The window

The menu bar has six menus: *VeraBASIC* (About), *File*, *Edit*, *Search*,
*Run* and *Help*. Their items come in groups between dotted lines, each
with its key at the right (*Save as... Ctrl Shift S*). Under the bar the
title band names the program and its folder; an asterisk says it has
changes not saved. The text takes the window in 78 columns of 8 x 8
cards, with a scroll bar at the right: its arrows scroll a line, a click
above or below the thumb a page. The status bar at the bottom shows:

- at the left, the **syntax of the keyword at the cursor**
  (`PRINT [#h,] [expr ...]`), from the keyword table, as you type; a
  message instead when there is one (an error, *Saved*, *Not found*),
  until the next key;
- at the right, the state (*Ready*, *Modified*, *Error* or *Stopped*) and
  the cursor's line and column (`12:5`).

*Edit > Line numbers* puts a gutter of line numbers at the left.

## Colours

The X16's bitmap has one ink colour, so VeraBASIC colours a program with
the paper of its cards and bold letters:

| What | How |
|---|---|
| keywords (`{PRINT}`, `{FOR}`, `{END IF}` ...) | **bold** |
| strings | on yellow paper |
| comments (`{REM}`, `'`) | on the sidebar's paper |
| numbers, names, operators | plain |
| the line of an error | red paper, the whole line |
| the line a program was stopped at | the selection's blue |

A line's colours come from that line alone: strings and comments end at
the line's end. In dark mode (Preferences) the same colours are the dark
palette's. The Classic theme has no colour map: there the keywords are
still bold, and an error's line is found by the cursor and the status bar.

## Typing

**Return** starts a new line indented as the one before; after a line
that opens a block (`{FOR}`, `{WHILE}`, `{REPEAT}`, `{DO}`, `{IF}` ...
`{THEN}` at the line's end, `{SELECT CASE}`, `{CASE}`, `{SUB}`,
`{FUNCTION}`, `{TRY}`, `{CATCH}`, `{ELSE}`, `{DIALOG}`, `{MENU}`) by two
more. A word that closes a block (`{NEXT}`, `{WEND}`, `{UNTIL}`, `{LOOP}`,
`{END IF}`, `{ELSE}`, `{CASE}` ...) typed at the inner indentation moves
back by two when you press Return (`{END SELECT}` by four). **Tab** types
two blanks.

The keys are Veranda Edit's: the arrows, Home, End, PgUp, PgDn (with
Shift to select, with Ctrl by words and to the text's ends), Backspace,
Delete, Esc (no selection); the mouse places the cursor, a drag selects, a
double click selects a word, the wheel scrolls.

| Keys | |
|---|---|
| Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Shift+S, Ctrl+Q | New, Open, Save, Save as, Quit |
| Ctrl+Z, Ctrl+X, Ctrl+C, Ctrl+V, Ctrl+A | Undo, Cut, Copy, Paste, Select all |
| Ctrl+Shift+F | Format |
| Ctrl+F, F3, Ctrl+H, Ctrl+L | Find and replace, Find next, Replace and find next, Go to line |
| Ctrl+K, F8 | Check; the next error |
| Ctrl+R, Ctrl+C | Run; Stop (while the program runs) |
| F5 | the last program's output again |
| F9, F6, F7, F10, F11 | a breakpoint; Continue, Step, Step over, Step out ([Debugging](debugging.md)) |
| Ctrl+W, F12, Tab | a watch; the trace; the keys to the debugger's pane |
| F1 | help on the keyword at the cursor |

Cut, Copy and Paste use the Text Scrap, as Veranda Edit and geoWrite do,
so text moves between them.

## Files

*File > Open* and *Save as* are Veranda's Open and Save dialog: the
Documents folder first, folders, and names of up to 63 characters
(`Counting the birds at the feeder.bas`). A program is saved as plain
Latin-1 text with the line ends it had (LF for a new one), so any PC
editor reads it, and `vbasic.py` checks and runs it on the PC. Saving
writes a new file first and then replaces the old one.

The example programs are in `/DOCUMENTS/VeraBASIC Examples`.

## Check, Run, Stop

**Check** (*Run > Check*, Ctrl+K) tokenizes and prepares the program on
the X16, as the runtime will before running it: every line, every block,
every name. The first error goes red, the cursor goes to it and the status
bar says what it is (`Line 6: NEXT j does not match FOR i% in line 2`).
**F8** (*Search > Next error*) checks again and goes to the next error
after that line, until *No more errors after line 6*.

**Run** (Ctrl+R) checks the program, then runs it. The editor's screen is
kept in RAM banks and the program gets the screen: a console window for
`{PRINT}` and `{INPUT}`, or its own windows and menus. When the program
ends:

- at its `{END}` (or its last line), a console program's output stays on
  the screen until you press a key or click; a program of windows goes
  straight back;
- stopped by **Ctrl+C** (or *Run > Stop*), the editor comes back with the
  line it was at in blue (*Stopped in line 12*);
- stopped by an error, the editor comes back at its line, in red, with the
  error in the status bar (`Error 11: Division by zero (line 3)`) and,
  whole, in a pane at the right: the line, the procedure and the
  statement in canonical form ([Debugging](debugging.md));
- stopped at a breakpoint, a step or `{STOP}`, the program is kept: the
  editor shows its line and the debugger's pane, and Continue (F6) sends
  it on ([Debugging](debugging.md)).

The *Run* menu has the debugger's commands under these: *Continue*,
*Step*, *Step over*, *Step out*, *Breakpoint*, *Add a watch...*, *Trace
(TRON)* and *The trace*.

The editor's screen comes back as it was. **F5** (*Run > Output*) shows
the last program's console again.

The editor and the program are one application: Alt+Tab puts both aside,
with the program running or not, and brings them back as they were. (With
512 KB of RAM there are not banks enough for that: the switcher offers to
quit VeraBASIC instead. Save first; on a 2 MB machine it goes aside.)

## Format

*Edit > Format* (Ctrl+Shift+F) rewrites the program in its **canonical
form**: keywords in upper case, names spelt as where they first appear,
one blank between words and none inside parentheses or before `,` `;` `:`,
literals as you spelt them, comments and `{DATA}` as they are, each line's
indentation kept (rounded to an even number of blanks). It is what
`vbasic.py canon` gives on the PC (guarantee G2, `docs/vbasic/FORMAT.md`).
Format needs a program that checks without errors. Undo takes it back when
the program fits the undo log.

## Help

**F1** opens the help at the keyword under the cursor (compound keywords
too: F1 on `IF` after `END` is *END IF*); on any other word, the contents.
*Help > Contents*, *Index*, *Tutorial* and *Error messages* open those
pages. In the help viewer:

| Keys | |
|---|---|
| Up, Down, PgUp, PgDn; the scroll bar | scroll |
| Tab, Shift+Tab | the next link, the one before |
| Return, a click | follow the link |
| Backspace | the page before |
| F1 | the contents |
| Esc | back to the program |

The help files are in `/VERANDA/HELP`: `KEYWORDS.HLP` (every keyword and
constant: syntax, text, an example; made from the keyword table),
`TUTORIAL.HLP` (the tutorial), `ERRORS.HLP` (the error messages) and
`EDITOR.HLP` (this chapter and the next, *Debugging*). They are plain text that Veranda Edit reads
too.

## Memory

The editor and the runtime share main RAM: the editor's own part takes
the interpreter's place while you edit, and the two change places when
you check or run. A program run from the editor has 2,436 bytes of main
RAM for its names (about 300 names; under VeraBASIC Run and in an
application 3,052). The editor keeps the text in RAM banks (64 KB at most for a
program), two banks for undo, and while a program runs six banks for its
screen when there are banks to spare; otherwise it draws its window again
when you come back.
