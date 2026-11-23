# 2. The language

This chapter describes VeraBASIC's language: its values, names,
expressions, statements and procedures, without Veranda's extensions
(windows, menus, graphics, files: chapter 3). Every listing here is a
whole program; the gate of phase 1 runs each in VeraBASIC Run and in the
reference interpreter and requires the same output.

## 2.1 Values and names

There are three types:

| Type | Suffix | Range | Example |
|---|---|---|---|
| integer | `%` | -32768 to 32767 | `count%` |
| float | none | about ±1.7E38, 9 digits | `price` |
| string | `$` | 0 to 255 Latin-1 characters | `name$` |

A name is a letter, then letters, digits and `_`, up to 32 characters, all
of them significant; case does not matter. `total`, `total%` and
`total$` are three different names. A keyword cannot be a name.

`OPTION INTEGER` anywhere in a program makes every name without a suffix
an integer; `DEFINT A-Z` does the same for names starting with the
letters given.

```basic
OPTION INTEGER
a = 7 / 2
b% = a * 10
c$ = "seven halves"
PRINT a; b%; c$
```

prints ` 3  30 seven halves`: `7 / 2` is 3.5, and assigning it to an
integer keeps the largest whole number not above it.

Numbers are written `12`, `1.5`, `.5`, `1E3`, `2.5E-3`, `$FF`
(hexadecimal) and `%1010` (binary). A whole number up to 32767 is an
integer; anything else is a float. Strings are written in quotes, `""`
for a quote inside one.

## 2.2 Expressions

From the highest priority:

| Operators | |
|---|---|
| `^` | power |
| `-` | negation |
| `*` `/` `\` `MOD` | multiply, divide (always a float), integer divide, remainder |
| `+` `-` | add, subtract; `+` also joins strings |
| `SHL` `SHR` | shift an integer's bits |
| `=` `<>` `<` `>` `<=` `>=` | compare: -1 (true) or 0 |
| `NOT` | |
| `AND` | |
| `OR` `XOR` | |

`AND`, `OR`, `XOR` and `NOT` work on the bits of integers, so with
comparisons (-1 or 0) they are the logical operators.

**Integers stay integers.** `+`, `-` and `*` of two integers give an
integer, computed without the float routines; when the result does not
fit in 16 bits it becomes a float, so `200 * 200` is 40000 and not an
error. `\` divides integers (rounding towards zero) and `MOD` gives the
remainder (with the sign of the dividend). `/` and `^` give floats.

```basic
PRINT 200 * 200; 7 \ 2; -7 \ 2; 7 MOD 3; -7 MOD 3
PRINT 7 / 2; 2 ^ 10; 2 ^ 0.5
PRINT 5 AND 3; 5 OR 3; 5 XOR 3; NOT 0
PRINT 1 < 2; "apple" < "banana"; 3 = 3.0
PRINT 1 SHL 4; 256 SHR 2
```

**Floats** are the X16 ROM's: the 5-byte format of V2 BASIC, about nine
digits, computed by the ROM's maths library, so a float result is what V2
BASIC on the same machine gives. They print as V2 prints them: a blank
or a minus sign first, then up to nine digits, an exponent for large and
small numbers.

```basic
PRINT 1 / 3; 2 / 3; 1E10; 1.5E-5
PRINT SQR(2); SIN(1); ATN(1) * 4; EXP(1); LOG(10)
PRINT INT(2.7); INT(-2.7); ABS(-4.5); SGN(-4.5)
```

`RND(1)` gives the next random number from 0 up to 1; a negative argument
starts a new sequence from it, so `RND(-1)` at the start makes a program
repeat its "random" numbers each time.

## 2.3 Printing and reading

`PRINT` writes values to the console. `;` joins them, `,` moves to the
next zone of 10 columns, and a `;` or `,` at the end keeps the line open.
A number prints with a blank before it (or its minus sign) and one
after. `TAB(n)` moves to column n, `SPC(n)` writes n blanks. The console
is 78 columns wide; a longer line goes on in the next row.

```basic
PRINT "Name"; TAB(12); "Count"
PRINT "Robin"; TAB(12); 3
PRINT "Wren", "Jay", "Owl"
PRINT "one";
PRINT " line"
PRINT "["; SPC(3); "]"
```

`INPUT "prompt"; a, b$` shows the prompt and `?`, and reads values typed
on one line separated by commas (text with a comma in it goes in quotes).
Too few values ask for more with `??`; a word where a number belongs
asks again with `Redo from start`. `LINE INPUT "prompt"; s$` reads a
whole line as it is. `GET k$` gives the next key, or `""` if none was
typed (it does not wait).

```basic
INPUT "Width, height"; w, h
PRINT "Area:"; w * h
LINE INPUT "A note: "; note$
PRINT "["; note$; "]"
```

```keys
3.5, 2
Buy seeds, and nails
```

## 2.4 Decisions

`IF` has a one-line form and a block form:

```basic
x% = 12
IF x% > 10 THEN PRINT "big" ELSE PRINT "small"
IF x% MOD 2 = 0 THEN PRINT "even": PRINT "and still even"
IF x% < 0 THEN
  PRINT "negative"
ELSEIF x% < 10 THEN
  PRINT "one digit"
ELSE
  PRINT "two digits or more"
END IF
```

`THEN` followed by a line number jumps there, as in V2 BASIC.

`SELECT CASE` compares one value with lists of values, ranges and
comparisons:

```basic
FOR n% = 1 TO 12 STEP 3
  SELECT CASE n%
    CASE 1, 2
      PRINT n%; "small"
    CASE 3 TO 9
      PRINT n%; "middle"
    CASE IS > 9
      PRINT n%; "large"
  END SELECT
NEXT
SELECT CASE "wren"
  CASE "robin", "wren": PRINT "a garden bird"
  CASE ELSE: PRINT "something else"
END SELECT
```

## 2.5 Loops

```basic
FOR i% = 10 TO 1 STEP -3: PRINT i%;: NEXT: PRINT
FOR x = 0 TO 1 STEP 0.25: PRINT x;: NEXT: PRINT
n% = 1
WHILE n% < 100: n% = n% * 3: WEND
PRINT n%
REPEAT: n% = n% - 7: UNTIL n% < 0
PRINT n%
DO
  n% = n% + 4
  IF n% > 20 THEN EXIT DO
LOOP
PRINT n%
DO WHILE n% > 10: n% = n% - 5: LOOP
PRINT n%
```

A `FOR` loop whose start is already past its end does not run at all
(V2 BASIC runs it once; the exception is a `FOR` inside a one-line `IF`,
which keeps V2's way). `EXIT FOR`, `EXIT WHILE`, `EXIT DO` and `EXIT
REPEAT` leave the innermost loop of their kind. `NEXT j, i` ends two
loops.

## 2.6 Jumps and labels

A line number or a label is a target for `GOTO`, `GOSUB`, `RESTORE` and
`RESUME`. A label is a name and a colon at the start of a line.

```basic
GOSUB Header
FOR k% = 1 TO 3
  ON k% GOSUB 100, 200, 300
NEXT
END
Header: PRINT "-- three subroutines --": RETURN
100 PRINT "one": RETURN
200 PRINT "two": RETURN
300 PRINT "three": RETURN
```

## 2.7 Procedures

`SUB` makes a procedure; `FUNCTION` one that gives a value. Parameters
are local to the procedure and take their arguments by value; `BYREF`
makes a parameter stand for the caller's variable, and an array
parameter (`a%()`) is always the caller's array. `LOCAL` makes more
local variables. Procedures may call themselves.

```basic
SUB Greet(who$, times%)
  LOCAL i%
  FOR i% = 1 TO times%: PRINT "Hello, "; who$: NEXT
END SUB
SUB Swap(BYREF a%, BYREF b%)
  LOCAL t%
  t% = a%: a% = b%: b% = t%
END SUB
FUNCTION Fact(n)
  IF n <= 1 THEN RETURN 1
  RETURN n * Fact(n - 1)
END FUNCTION
FUNCTION Initials$(first$, last$)
  Initials$ = LEFT$(first$, 1) + LEFT$(last$, 1)
END FUNCTION
Greet "Robin", 2
x% = 1: y% = 2: Swap x%, y%: PRINT x%; y%
PRINT Fact(10); Initials$("Ada", "Lovelace")
CALL Greet("Wren", 1)
```

A SUB is called by its name and its arguments, or with `CALL`. A
FUNCTION's value is set by assigning to its name or by `RETURN value`.
`EXIT SUB` and `EXIT FUNCTION` return at once. A name a procedure does not
make local is the program's (global) variable; `SHARED` says so on
purpose.

Procedure frames, `FOR` loops and `GOSUB`s live on the BASIC stack in a
RAM bank of its own, about 8 KB: a recursion several hundred calls deep
is fine, a runaway one ends with error 16, *Stack overflow*.

## 2.8 Arrays

`DIM a%(100)` makes an array of 101 elements, indices 0 to 100; up to
three dimensions. Arrays live in RAM banks and may be large: `OPTION
MEMORY n` gives the variables' arrays and strings up to n banks of 8 KB
(4 without it). An array used without `DIM` has 11 elements in each
dimension, as in V2 BASIC. `UBOUND(a, d)` gives a dimension's largest
index; `REDIM` makes an array again with new sizes.

```basic
DIM squares%(10), grid(2, 3), names$(2)
FOR i% = 0 TO 10: squares%(i%) = i% * i%: NEXT
FOR r% = 0 TO 2: FOR c% = 0 TO 3: grid(r%, c%) = r% + c% / 10: NEXT c%, r%
names$(0) = "Robin": names$(1) = "Wren": names$(2) = "Jay"
PRINT squares%(10); grid(2, 3); names$(1); UBOUND(grid, 2)
SUB Total(a%())
  LOCAL i%, s%
  FOR i% = 0 TO UBOUND(a%): s% = s% + a%(i%): NEXT
  PRINT "total"; s%
END SUB
Total squares%()
```

## 2.9 Strings

```basic
s$ = "Blackbird"
PRINT LEFT$(s$, 5); "|"; RIGHT$(s$, 4); "|"; MID$(s$, 3, 4); "|"; LEN(s$)
PRINT ASC("A"); CHR$(66); STR$(42); VAL("3.25") * 2
t$ = s$ + " and " + "Thrush"
PRINT t$; LEN(t$)
PRINT "abc" < "abd"; "Zebra" < "apple"
```

Strings are values: assigning one copies it. They live in a heap in RAM
banks; when the heap is full a collector moves the strings still in use
together in one pass. Each string knows the variable that holds it, so
the collection never searches: a heap of 64 KB is collected in a fraction
of a second, and programs do not stall the way V2 BASIC's did.

## 2.10 Data

`DATA` lines hold values that `READ` takes in order; `RESTORE` starts
again, at the first `DATA` or at a line given.

```basic
READ n%
FOR i% = 1 TO n%
  READ bird$, count%
  PRINT bird$; TAB(12); count%
NEXT
RESTORE Prices
READ p1, p2: PRINT p1 + p2
DATA 3
DATA Robin, 4, "Blue tit", 7, Wren, 1
Prices: DATA 2.5, 1.25
```

`CONST name = value` names a value that the program cannot change.

## 2.11 Errors

`TRY` runs statements; an error among them goes to `CATCH` instead of
stopping the program. `ERR` is the error's number, `ERR$` its message,
`ERL` its line (the line's number, or its line in the source). `ERROR n,
message` raises an error of your own; 200 to 255 are free for programs.

```basic
FUNCTION Inverse(x)
  Inverse = 1 / x
END FUNCTION
TRY
  PRINT Inverse(4)
  PRINT Inverse(0)
CATCH
  PRINT "Caught error"; ERR; "("; ERR$; ") in line"; ERL
END TRY
TRY
  ERROR 200, "No birds today"
CATCH
  PRINT ERR; ERR$
END TRY
```

An error in a procedure called from inside `TRY` ends the procedure (and
any between) and goes to the `CATCH`. V2's `ON ERROR GOTO line`, `RESUME`,
`RESUME NEXT` and `ON ERROR GOTO 0` work too. `STOP`, Ctrl+C and the STOP
key raise error 1, *Stopped*, which no `TRY` catches.

### The error numbers

| | | | |
|---|---|---|---|
| 1 | Stopped | 13 | Type mismatch |
| 2 | Syntax error | 14 | String too long |
| 3 | RETURN without GOSUB | 15 | Formula too complex |
| 4 | Out of DATA | 16 | Stack overflow |
| 5 | Illegal quantity | 17 | RESUME without error |
| 6 | Overflow | 18 | NEXT without FOR |
| 7 | Out of memory | 19 | Wrong number of arguments |
| 8 | Undefined line | 20 | Not available yet (a Veranda statement of a later phase) |
| 9 | Subscript out of range | 21 | Made by a newer VeraBASIC |
| 10 | Array already dimensioned | 22 | Not inside a SUB |
| 11 | Division by zero | 23 | BYREF needs a variable |
| 12 | Not an array | 200-255 | the program's own |

## 2.12 V2 listings

A V2 BASIC listing with blanks between its words runs as it is, in the
console:

```basic
10 REM SQUARES AND A STRING BACKWARDS
20 FOR I=1 TO 5
30 PRINT I;I*I
40 NEXT I
50 A$="COMMODORE":B$=""
60 FOR I=LEN(A$) TO 1 STEP -1:B$=B$+MID$(A$,I,1):NEXT
70 PRINT B$
80 IF I<1 GOTO 100
90 PRINT "NOT REACHED"
100 END
```

What differs: there is no text screen at `$0400` (`POKE` writes main RAM
below `$A000`, which a program may use from `$7F00` with care); `LOAD`,
`SAVE` and `LIST` are the editor's; a `FOR` whose start is past its end
does not run; `FRE(0)` gives the free bytes of the variables' banks.

## 2.13 Memory and speed

| | |
|---|---|
| a program's tokens | up to 64 KB, in RAM banks (7.75 KB of them a bank) |
| names | a program's names in main RAM, 8 bytes each: about 300 |
| strings and arrays | `OPTION MEMORY n` banks (4 by default, 24 at most) |
| the BASIC stack | one bank: procedures, loops, `GOSUB`s, `TRY` |
| floats | the X16 ROM's maths library, called through its jump table |
