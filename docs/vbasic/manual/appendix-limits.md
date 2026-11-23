# Appendix C: memory limits

VeraBASIC runs on a Commander X16 with 512 KB of RAM banks or more. A
program's memory is in three places: main RAM for its names, RAM banks
for everything else, and the screen.

## A program

| What | Limit | When it is passed |
|---|---|---|
| the source text | 64 KB (65,280 bytes) | *The program is too big* |
| a source line | 255 characters | *Line too long* |
| a string | 255 characters | error 14, *String too long* |
| the tokens (record 1) | 64 KB, in 8 banks of 7.75 KB | *Program too big* |
| names | 512, with 7.9 KB of spellings (the X16's tokenizer); in main RAM 8 bytes each at run time, about 290 under VeraBASIC Run, an application or the editor | *Too many names*; *Too many names for main RAM* |
| procedures | 128, each with 100 parameters and `{LOCAL}`s | *Program too big* |
| blocks open at once | 24 (`{FOR}`, `{IF}`, `{WHILE}` ... nested in one place) | *Program too big* |
| numbered lines | 2,048 | *Program too big* |
| `{DATA}` items | 4,096 | *Program too big* |
| arrays and strings | the variables' banks: 4 (32 KB) by default, `{OPTION}` `{MEMORY}` n up to 24 (192 KB) | error 7, *Out of memory* |
| the BASIC stack | one bank, 8 KB: about 300 nested procedures, loops, `{GOSUB}`s and `{TRY}`s | error 16, *Stack overflow* |
| an expression | as deep as the value stack holds | error 15, *Formula too complex* |
| windows | 4 | error 25, *No such window* |
| files open | 3 | error 51, *Too many files* |
| timers | 8 (`{TIMER}` 1-8) | error 5, *Illegal quantity* |
| sprites | 2-7 (the kernel keeps the others) | error 5, *Illegal quantity* |
| file names | 63 characters, folders in them, 64 in all | the kernel's error |

## RAM banks at 512 KB

The emulator and a 512 KB X16 have 43 banks for programs once Veranda's
kernel has its own (fewer with fonts loaded or the wallpaper's picture).

| Program | Banks at rest | Running a small program |
|---|---|---|
| VeraBASIC Run | 13 | about 21 (the program's tokens, its stack, its 4 variable banks) |
| an application made by VeraBASIC | 13, and one more for each 8 KB of its program | about 22 |
| VeraBASIC, the editor | 32 (its records, the text's 2, undo's 2) | about 40; the editor's screen is kept in 6 more when 16 are free |

The switcher keeps 18 banks free for the desktop, so VeraBASIC Run and
a small application can be put aside at 512 KB; the editor can be at
2 MB, and at 512 KB its switcher box offers to quit it instead.

## Main RAM

A program's names take 8 bytes each in main RAM, with its procedures'
tables. The room is 2,436 bytes in the editor and 3,052 under
VeraBASIC Run and in an application. `{POKE}` and `{PEEK}` reach main
RAM below `$A000`; `$7F00`-`$7FFF` is safe for a program's own bytes
when it has few names.
