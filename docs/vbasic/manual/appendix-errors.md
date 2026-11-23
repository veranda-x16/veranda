# Appendix A: error messages

The run-time errors, from the same table as the runtime's messages and
the help's pages (`ERRORS.HLP`; tools/vbgen.py writes all three). The
editor shows one whole in the debugger's pane (chapter 6): `Error 13,
Type mismatch, in line 57 (SUB Tick): total% = name$`; a file's error
has the kernel's code too, `(kernel 5)`. `{TRY}` ... `{CATCH}` and
`{ON}` `{ERROR}` `{GOTO}` catch them: `{ERR}` is the number, `{ERR$}` the
message, `{ERL}` the line, `{ERRFILE}` the kernel's error.

| Number | Message | What it means |
|---|---|---|
| 1 | Stopped | Ctrl+C, the STOP key, Run > Stop or (in VeraBASIC Run) a STOP statement stopped the program. In the editor a STOP statement stops it as a breakpoint does, to go on (F6). |
| 2 | Syntax error | A statement the runtime could not read: a word missing or one too many. |
| 3 | RETURN without GOSUB | RETURN came with no GOSUB to go back to. |
| 4 | Out of DATA | READ found no more DATA items: the program read more than its DATA lines hold. RESTORE starts them again. |
| 5 | Illegal quantity | A number out of the range the statement or function takes: a negative length, a colour above 15, CHR$(300). |
| 6 | Overflow | A number too large for a float, or an integer (%) outside -32768 .. 32767 where an integer is needed. |
| 7 | Out of memory | The program needs more RAM banks than there are (its arrays, its strings, OPTION MEMORY), or more room for names in main RAM. |
| 8 | Undefined line | GOTO, GOSUB or THEN names a line number the program has not got. |
| 9 | Subscript out of range | An array index below 0 or above its DIM. |
| 10 | Array already dimensioned | DIM of an array that is already dimensioned; REDIM changes its size. |
| 11 | Division by zero | A division (/, \ or MOD) by zero. |
| 12 | Not an array | A name used with an index that is not an array. |
| 13 | Type mismatch | A string where a number is needed, or a number where a string is. |
| 14 | String too long | A string longer than 255 characters. |
| 15 | Formula too complex | An expression nested too deep for the value stack: split it with a variable. |
| 16 | Stack overflow | Too many FOR, GOSUB, procedure or TRY levels at once (about 300): a recursion that does not end? |
| 17 | RESUME without error | RESUME outside an ON ERROR handler. |
| 18 | NEXT without FOR | NEXT with no FOR open. |
| 19 | Wrong number of arguments | A SUB, FUNCTION or built-in function called with the wrong number of arguments. |
| 20 | Not available yet | A statement this version of VeraBASIC has not got yet. |
| 21 | Made by a newer VeraBASIC | The program document was made by a newer VeraBASIC than this one. |
| 22 | Not inside a SUB | EXIT SUB, RETURN with a value or LOCAL outside a SUB or FUNCTION. |
| 23 | BYREF needs a variable | A BYREF parameter was given a value, not a variable. |
| 24 | Font not found | FONT names a font that is not in /VERANDA/FONTS. |
| 25 | No such window | A window number with no WINDOW open. |
| 26 | Too many menus or items | More menus or menu items than Veranda's menu bar holds. |
| 50 | File not found | No file of that name in the folder. The message has the kernel's error too, (kernel 5), as ERRFILE gives it. |
| 51 | Too many files | More than three files open at once. |
| 52 | Bad file number | A file number outside 1 .. 255. |
| 53 | File not open | PRINT #, INPUT # or CLOSE of a file number that is not open. |
| 54 | File already open | OPEN of a file number that is open already. |
| 55 | Bad file mode | A file opened for reading written to, or the other way round, or a mode other than "r", "w", "a", "m". |
| 56 | Input past end | INPUT #, LINE INPUT # or GET # past the file's end: test EOF first. |
| 57 | Disk error | The card or the folder said no. The message has the kernel's error too, (kernel n), as ERRFILE gives it. |
| 58 | File exists | A file or folder of that name is there already. |
| 59 | Bad picture | A picture string that is not one (PICTURE$ makes them). |
| 60 | Not in a DIALOG | LABEL, FIELD or BUTTON outside a DIALOG block. |

## Check's messages

Check (Ctrl+K), Run before a program starts, and `vbasic.py check` read
the whole program first and report these with their line:

- the tokenizer: *Unexpected character*, *Line too long*, *String too
  long*, *Number too big*, *Name too long*, *Line number out of range*,
  *Too many names*, *Program too big*;
- the blocks: *X without Y* (*NEXT without FOR*), *Y missing for X in
  line N*, *NEXT j does not match FOR i*, *Two ELSE parts*, *CASE expected
  after SELECT CASE*, *THEN missing after IF*;
- procedures: *SUB B inside SUB A*, *defined twice*, *EXIT SUB outside
  SUB*, *LOCAL outside a SUB or FUNCTION*;
- names: *Undefined label X*, *Undefined line N*, *Undefined SUB X*,
  *Label X defined twice*, *Cannot assign to constant X*.

Make application adds its own (chapter 7): *APP: NAME "...", CLASS
"...", TILE SKY ...* for an `{APP}` line it cannot read, *TILE DATA: 32
rows of 32 "#" and "."*, *APP DOCUMENTS: up to 4 of 1-4 letters*, *The
name: 1-63 characters*; and VeraBASIC Run, given a program made by a
later version, *Made by a newer VeraBASIC*.
