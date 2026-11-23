# 8. Coming from V2 BASIC

VeraBASIC keeps the core of Commodore BASIC V2, the BASIC of the C64 and
of the X16's ROM: line numbers, `{GOTO}`, `{GOSUB}`, `{FOR}` ... `{NEXT}`,
`{IF}` ... `{THEN}`, `{DATA}` and `{READ}`, `{PRINT}` with `;` and `,`,
the string functions, floats in the ROM's own format. A V2 listing with
blanks between its words runs as it is, in the console window:

```basic
10 REM A V2 PROGRAM, AS IT IS
20 DIM N(10)
30 FOR I=1 TO 10:N(I)=I*I:NEXT I
40 S=0:FOR I=1 TO 10:S=S+N(I):NEXT
50 PRINT "SUM OF SQUARES";S
60 GOSUB 100
70 END
100 PRINT "IN THE SUBROUTINE":RETURN
```

## Bringing a .PRG in: vbasic.py import

A program saved by the C64 or the X16's BASIC is tokenized: its keywords
are single bytes, and a crunched line (`FORI=1TO9`) has no blanks at
all. `vbasic.py import` turns such a `.PRG` into a `.bas` file:

```
python3 -I -B tools/vbasic.py import SQUARES.PRG -o "Squares.bas"
```

- every keyword token becomes its word with a blank before and after
  it, so `FORI=1TO9` becomes `FOR I=1 TO 9`;
- text in quotes, after `{REM}` and in `{DATA}` stays as it was;
- PETSCII becomes Latin-1: the letters as letters (the shifted set as
  lower case); a control character in quotes (clear the screen, a colour)
  becomes `" + CHR$(147) + "`;
- an X16 BASIC statement (the ROM's extended tokens, `$CE` and a byte:
  `SCREEN`, `LINE`, `RECT` ...) has no VeraBASIC form: it is kept as a
  `{REM}` and named in a warning, for you to rewrite with the Veranda
  statements (chapter 3).

Then open it in VeraBASIC (or `vbasic.py check` it), and Check (Ctrl+K).
*Format* gives it VeraBASIC's canonical form if you want it.

## What differs

| V2 | VeraBASIC |
|---|---|
| names: two significant characters (`COUNT` and `CO` are one variable) | every character counts (`count` and `co` are two); names are case-blind |
| keywords inside names (`FORM` is `FOR M`) | a keyword is a whole word: `form` is a name |
| floats unless `%` or `$` | the same; `{OPTION}` `{INTEGER}` makes unsuffixed names 16-bit integers, much faster |
| a `{FOR}` loop runs once even when its start is past its end | it does not run |
| `{IF}` ... `{THEN}` on one line | that, and block `{IF}` ... `{ELSE}` ... `{END IF}` |
| `{GOSUB}` and line numbers only | `{SUB}` and `{FUNCTION}` with arguments and `{LOCAL}` variables, labels, `{WHILE}`, `{REPEAT}`, `{DO}`, `{SELECT CASE}` |
| errors end the program | `{TRY}` ... `{CATCH}`, `{ON}` `{ERROR}` `{GOTO}` and `{RESUME}` |
| the screen at `$0400`, `{POKE}` 53280 for the border | no text screen: the console window; colour with `{PAPER}`; `{POKE}` and `{PEEK}` reach main RAM below `$A000` |
| `LOAD`, `SAVE`, `LIST`, `RUN` | the editor's File and Run menus |
| `{OPEN}` 1,8,2,"FILE,S,W" | `{OPEN}` `#1, "A long file name.txt", "w"`: names up to 63 characters, folders |
| `{GET}` from the keyboard buffer | `{INKEY$}`, or `{ON}` `{KEY}` `{CALL}` for a windowed program |
| `{TI}` and `{TI$}` | `{TI}` (frames), `{TIME$}`, `{DATE$}`; `{TIMER}` for events |
| `{FRE}`(0) | the free bytes of the variables' banks |
| `{SYS}` | allowed, at your own risk: Veranda's memory map is not the X16 ROM's |

## Speed

The same V2 program runs about as fast as on the X16's BASIC (the floats
are the ROM's own routines); with `{OPTION}` `{INTEGER}` at the top and
`%` on the floats you do not need, loops run three to six times faster
(gate `vb_speed`, the Rugg/Feldman benchmarks).

```basic
10 OPTION INTEGER
20 T=0
30 FOR I=1 TO 1000:T=T+I MOD 7:NEXT
40 PRINT T
```
