# Appendix D: the ROM's maths

VeraBASIC's floats are the Commander X16 ROM's own: the 5-byte format of
Commodore BASIC V2 (an exponent byte and a 4-byte mantissa with its
sign), about nine significant digits, from 2.9E-39 to 1.7E+38. Every
float operation (`+ - * /`, `^`, `{SQR}`, `{SIN}`, `{LOG}`, `{VAL}`,
`{STR$}` ...) is a call into the ROM's maths library through its public
jump table, so a VeraBASIC program computes what the same V2 program
computes on the X16, to the last bit.

## Called, not copied

The maths library belongs to the ROM. VeraBASIC carries none of its code
or tables: the runtime calls the jump table's entries (`FADD`, `FMULT`,
`FDIV`, `FOUT` and the others) at run time, with the ROM bank they are in
mapped, and leaves the library's zero page (`$A9`-`$D3`) alone. So the
library's licence and origin stay with the ROM (the plan's section 10).

## Two things the runtime does itself

- **Reading a number.** The tokenizer turns a float written in the text
  into its 5 bytes once, when the program is checked. It rounds the
  spelling correctly (the PC with Python's fractions, the X16 with big
  integers in overlay 5), and does not use the ROM's `VAL` routine,
  which differs in the last bit for some spellings. `{VAL}` at run time
  is the ROM's.
- **Integers.** With `{OPTION}` `{INTEGER}` or a `%` name, values are
  16-bit integers worked out by the runtime: no ROM call, and 3-6 times
  faster. A float is made from an integer only where an expression mixes
  them.

## The reference on the PC

`vbasic.py run --rom rom.bin` runs the ROM's own maths routines in a
small 65C02 emulator (`tools/vbrom.py`), so the reference interpreter's
floats are the X16's. Without a ROM image it uses the PC's doubles and
says the floats are approximated: the last digit of a result can differ.

```basic
' the same digits on the X16 and in the reference with --rom
x = 1 / 3
PRINT x, x * 3, SQR(2), 10 ^ 0.5
PRINT INT(-2.5), 7 MOD 3, 2 ^ 31
```

## The ROM's version

The jump table has kept its entries through the X16's ROM releases. The
gates run under release R49; a ROM whose maths entries moved would be
found by gate `vb_core`, which compares every float result with the
reference's.
