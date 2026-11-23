# The VeraBASIC manual

VeraBASIC is a structured BASIC for Veranda on the Commander X16: optional
line numbers, procedures with local variables, long names, integers,
floats and strings, and statements for Veranda's windows, menus, dialogs,
graphics, files with long names, sound and the switcher. A program is a
plain `.bas` text file; the editor *VeraBASIC* runs it, *VeraBASIC Run*
runs finished programs, and *Make application* turns one into a program
of its own.

This is the whole manual (docs/DECISIONS.md V85-V90, V93, V97, V99). The
reference is generated; the chapters were written in the phases named
below. `vbasic.py doc OUTDIR` makes it into HTML (a page a chapter) and
one PDF, and the reference card into a two-page PDF (docs/vbasic/TOOLS.md);
on the card it is `/VERANDA/HELP/MANUAL.HLP` (Help > Contents > Manual in
the editor) and `Reference card.pdf`. In these pages a keyword written as `{PRINT}` is
checked against the keyword table when the manual is generated, so a
renamed keyword breaks the build, not the manual.

| Chapter | Contents | Phase |
|---|---|---|
| [1. Getting started](getting-started.md) | a first program, a double click on a `.bas` file (VeraBASIC) or a program document (VeraBASIC Run), `vbasic.py check`, `build` and `run`, VeraBASIC Run, its console (the editor: phase 5) | **1, 2** and 5 |
| [2. The language](language.md) | types, names, expressions, blocks, procedures, arrays, strings, errors, `DATA`, console input and output | **1** |
| [3. Veranda extensions, part 1](extensions.md) | the program model and events, windows, menus, graphics, text and fonts, colour, the mouse and the keys, time, sound; every statement with a listing and its kernel call | **3** |
| [3b. Veranda extensions, part 2](extensions2.md) | files with long names and folders, message boxes, `DIALOG` blocks, the Open and Save dialog, the clipboard, pictures, icons, tiles, sprites; every statement with a listing (its boxes answered by a mouse script) | **4** |
| [Example programs](../examples) | *Notes* (Open and Save with long names, the clipboard), *Dice* (icons, a sprite, sounds), *Address book* (files, a `DIALOG`), *Tiles* (a page of tiles); each run by gate `vb_files` with a mouse script | **4** |
| [4. Tutorial: a windowed app in an hour](tutorial.md) | seven steps to *Bird Watch*: a window, menus, a counter, a timer, the mouse, colour and keys, sound | **3** |
| [5. The editor](editor.md) | the window and its status bar, colours, typing and Return's indentation, files with long names, Check and F8, Run and Stop, the error jumps, Format, F1 and the help viewer | **5** |
| [6. Debugging](debugging.md) | breakpoints and `{STOP}`, the pane: the call stack, the variables (an array's elements, a value changed), watches; Step, Step over, Step out; the program's screen kept; `{TRON}` and the trace pane; the error messages | **6** |
| [4. Events and the program model](events.md) | the main lines and the handlers, the queue, what an event knows, errors in handlers, put aside, a program's end | **7** |
| [7. Making applications](making-apps.md) | what an application is, the `{APP}` lines, tiles, documents and `{DOCUMENT$}`, *File > Make application...* and `vbasic.py app`, Bird Watch | **7** |
| [8. Coming from V2 BASIC](from-v2.md) | `vbasic.py import`, what differs, speed | **7** |
| [The language reference](reference.md) | every keyword and constant: syntax, text, example, the kernel calls | **0: generated** |
| [Appendix B: tokens](tokens.md) | the token list | **0: generated** |
| [The reference card](refcard.md) | every statement and function on a line, the operators, the errors (version 0) | **1: generated** |
| [Appendix A: error messages](appendix-errors.md) | every run-time error, what it means; Check's messages (generated, as `ERRORS.HLP`) | **7: generated** |
| [Appendix C: memory limits](appendix-limits.md) | a program's limits, RAM banks at 512 KB, main RAM | **7** |
| [Appendix D: the ROM's maths](appendix-maths.md) | the floats, called not copied, what the runtime does itself | **7** |

The formats are in [../FORMAT.md](../FORMAT.md), the PC tools in
[../TOOLS.md](../TOOLS.md).

## What phase 0 fixes

- **The keyword table** (`vbasic/keywords.tbl`): every keyword's token,
  which is part of the file format from now on.
- **The source text and its canonical form:** keywords in upper case, one
  blank between words, names as first written. *Format* in the editor
  and `vbtokens.py canon` give it.
- **Names and keywords:** a keyword is a whole word and cannot be a name.
  `{PRINT}` is a keyword, `printer` a name, `{KEY$}` a keyword, `key%` a
  name. Colour, pointer, style, wave and folder names (`YELLOW`, `BUSY`,
  `BOLD`, `PULSE`, `DOCS`) and the kernel's `KEY_` and `SND_` codes are
  predefined constants: names a program may read but not assign.
- **Colours that are keywords:** `{PAPER}`, `{INK}`, `{SELECT}` and
  `{TITLE}` are statements or words, so they are also the colour numbers
  0, 1, 4 and 5 where an expression is expected: `{PAPER} 0, 2, 80, 1,
  {SELECT}`.
- **A label** is a name and `:` at the start of a line. A `{SUB}` without
  arguments at the start of a line followed by `:` is called with
  `{CALL}`.
- **V2 listings** with blanks between their words run as they are;
  crunched ones (`FORI=1TO9`) come in through `vbasic.py import` (phase
  2), which reads the tokenized `.PRG`.
