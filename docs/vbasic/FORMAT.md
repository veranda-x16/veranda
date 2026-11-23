# VeraBASIC: the token and file formats

Token format **1** (docs/DECISIONS.md V85). This page is the contract
between the PC tokenizer (`tools/vbtokens.py`), the X16 tokenizer and
runtime (phases 1 and 2), the editor and the program documents. Gate
`vb_spec` (`tools/gate_vb_spec.sh`) checks it.

**Once released, tokens are part of the file format.** A new keyword gets
a new number; a number is never given to another keyword (a removed one
stays in `vbasic/keywords.tbl` as a `retired` line). A change to anything
below raises the format number in the program header, and a runtime that
meets a newer number refuses the program with *Made by a newer
VeraBASIC*.

## 1. Where things come from

| Source | Makes | By |
|---|---|---|
| `vbasic/keywords.tbl` | every keyword: token, kind, arguments, overlay, kernel calls, syntax, help, example, see also | hand |
| | `vbasic/gen/tokens.inc` (ca65), `tools/vbtokens_gen.py` (Python), `vbasic/gen/HELP/KEYWORDS.HLP`, `docs/vbasic/manual/reference.md`, `docs/vbasic/manual/tokens.md` | `tools/vbgen.py` |
| a `.bas` file | the token stream, then the prepared program | `tools/vbtokens.py`; on the X16, VeraBASIC Run's tokenizer (`apps/vbasic/vbtok.s`, `vbprep.s`, `vbfloat.s`: overlays 2-5), byte for byte the same (G3) |
| the prepared program | the program document `Name.cvt` | `vbasic.py build` (`vbtokens.py tok`), later the editor |

The head of `keywords.tbl` describes its line format. `vbgen.py` fails
when a keyword or constant lacks its syntax line, its help text or its
example, and on every inconsistency it can see (section 10).

## 2. The source text

- **Characters:** Latin-1; lines end with LF (CR LF and CR are read too).
  Trailing blanks are not part of a line. A tab counts as two columns of
  indentation.
- **Line numbers:** a line may start with a number, 1 to 65535: a label
  that is a number. Line numbers need not be in order but may not repeat.
- **Labels:** a name followed by `:` as the first statement of a line
  (after its number, if any) is a label: `Start:`. So a SUB without
  arguments that starts a line followed by `:` must be called with
  `CALL`.
- **Indentation:** the leading blanks (after the line number and one
  blank) divided by two, 0 to 15, is kept in the line's flags.
- **Names:** a letter, then letters, digits and `_`; up to 32 characters
  (the suffix not counted); then optionally `%` (integer) or `$`
  (string). Case does not matter: `Total%` and `TOTAL%` are one name.
  `a`, `a%` and `a$` are three names.
- **Keywords** are whole words, matched with their suffix: `LEFT$` is a
  keyword, `LEFT` is a name, `FORI` is a name (crunched V2 text like
  `FORI=1TO9` is not read; V2 programs come in through `vbasic.py
  import`, phase 2, which reads the tokenized form). A keyword cannot be
  a name: `SUB Show` is an error, since `SHOW` is the word of `MENU SHOW`.
  `?` is `PRINT`.
- **Compounds:** two keywords with blanks between them that form one
  token: `END IF`, `END SUB`, `END FUNCTION`, `END SELECT`, `END TRY`,
  `END MENU`, `END DIALOG`, `EXIT FOR`, `EXIT WHILE`, `EXIT DO`,
  `EXIT REPEAT`, `EXIT SUB`, `EXIT FUNCTION`, `SELECT CASE`, `CASE ELSE`,
  `LINE INPUT`, `DIALOG RESULT` (the table's `vb_compound`).
- **Numbers:** `123`, `1.5`, `.5`, `1.`, `1.5E3`, `2e-3` (decimal);
  `$FF` (hexadecimal, at most `$FFFF`); `%1010` (binary, at most 16
  digits). A decimal number without `.` or `E` up to 32767 is an integer;
  any other decimal number is a float (40000 is a float).
- **Strings:** `"text"`, `""` for a quote, at most 255 bytes. A string
  open at the end of the line ends there.
- **Comments:** `REM` or `'` to the end of the line, kept byte for byte.
- **DATA** at a statement's start: the items up to `:` (outside quotes)
  or the line's end, each kept byte for byte, blanks included.
- **Punctuation:** `( ) , ; : # + - * / ^ \ = < >` and the two-character
  operators `<=` `<>` `>=` (tokens). Any other character outside strings
  and comments is the error *Unexpected character*.

## 3. The token stream

| Byte | Tag (`tokens.inc`) | Meaning | Followed by |
|---|---|---|---|
| `$00` | `TAG_EOL` | the end of a line record | |
| `$01` | `TAG_INTDEC` | integer, decimal spelling | 2 bytes, little-endian |
| `$02` | `TAG_INTHEX` | integer, hexadecimal spelling | 2 bytes |
| `$03` | `TAG_INTBIN` | integer, binary spelling | 2 bytes |
| `$04` | `TAG_FLOAT` | float | 5-byte value (section 3.2), length, the spelling as written |
| `$05` | `TAG_STRING` | string | length, bytes (quotes undoubled) |
| `$06` | `TAG_VAR` | variable, array or function name | slot, 2 bytes: a symbol number, or `$8000` + a frame slot (a local, section 5.2) |
| `$07` | `TAG_LINEREF` | line-number reference | the number (2), the target record's address (3: 0 in the file, the runtime caches it) |
| `$08` | `TAG_NAMEREF` | label or procedure reference | symbol (2), target (3: filled by prepare) |
| `$09` | `TAG_COMMENT` | comment (after `REM` or `'`) | length, raw text |
| `$0A` | `TAG_DATA` | one `DATA` item | length, raw text |
| `$0B` | `TAG_BLOCK` | block partner offset | 2 bytes (filled by prepare) |
| `$0C-$1F` | | not used | |
| `$20-$7F` | | the punctuation above, as itself (`'` starts a comment) | |
| `$80-$FE` | `TK_*` | first page: the core language (statements, functions, operators, words) | |
| `$FF nn` | `TAG_EXT`, `TX_*` | second page, nn `$01-$FF`: the Veranda extensions | |

The token numbers are in `docs/vbasic/manual/tokens.md` (generated).
Format 1 has 112 first-page and 115 second-page keywords; 15 first-page
and 140 second-page numbers are free.

### 3.1 What the context decides

The tokenizer works one line at a time and keeps only this much context:

- **`$0B` follows a block keyword** (`IF`, `ELSEIF`, `ELSE`, `WHILE`,
  `WEND`, `REPEAT`, `UNTIL`, `DO`, `LOOP`, `FOR`, `NEXT`, `SELECT CASE`,
  `CASE`, `CASE ELSE`, `SUB`, `FUNCTION`, `TRY`, `CATCH`, the `EXIT`s,
  `DIALOG`: the `block` flag) **when it starts a statement**, and always
  after `ELSE`. The words inside a statement carry none: `DO WHILE x`,
  `LOOP UNTIL x`, `RESUME NEXT`.
- **Line and label references:** after `GOTO`, `GOSUB`, `RESTORE` and
  `RESUME` (flag `ref=line`) a number is a `$07` and a name a `$08`; after
  `GOTO` and `GOSUB` the list goes on after each `,` (`ON n GOTO 10, 20`).
  After `THEN` and `ELSE` (`ref=stmt`) a number is a `$07`; anything else
  starts a statement.
- **Procedure references:** a name after `CALL`, `SUB` and `FUNCTION`
  (`ref=proc`) is a `$08`; so is a name standing alone in a `p` position
  of a statement's arguments (`ITEM text$, Handler`, `ICON ..., Handler`).
- **A name that starts a statement** is a variable (`$06`) when `=`
  follows it, or `(...)` and then `=` (an array element); a label when it
  is the line's first statement and `:` follows; otherwise a SUB call
  (`$08`).
- Every other name is a `$06`: variables, arrays, constants and FUNCTION
  calls. Prepare tells them apart.
- `DATA` is raw only at a statement's start; in an expression
  (`FOLDER$(DATA)`) it is the plain token.

### 3.2 Floats

The X16 ROM's 5-byte format (as V2's): byte 0 the exponent + 128 (0 =
zero), bytes 1-4 the mantissa, most significant first, with its leading 1
replaced by the sign (bit 7 of byte 1). Value = 0.1mmm...(binary) x
2^(exponent - 128). The tokenizer rounds the decimal spelling correctly
(to nearest, ties to even); a value above about 1.7E38 is the error
*Number too big*, one below about 2.9E-39 is 0. Examples: 1 = `81 00 00
00 00`, 0.1 = `7D 4C CC CC CD`, -1 = `81 80 00 00 00`, 10 = `84 20 00 00
00`.

The spelling is kept (length and bytes) so that the canonical form shows
the number as it was written.

VeraBASIC Run's tokenizer gives the same 5 bytes (G3; DECISIONS V87):
overlay 5 takes the digits as one big integer M (leading zeros dropped)
and the decimal exponent X of the spelling. A value of 10^39 or more is
*Number too big* and one below 10^-39 is 0 at once; otherwise, for X >= 0
it multiplies M by ten X times, for X < 0 it shifts M left by k = 4|X| +
35 - bits(M) bits (0 at least) and divides by ten |X| times, keeping
whether any division left a remainder. The top 32 bits are the mantissa;
the next bit and whether anything below it (or a remainder) is not zero
round it, to nearest, ties to even, exactly as the PC's fractions do.
The X16 ROM's own conversion (`val_1`) is not used: it differs in the
last bit for some spellings.

## 4. Line records

A program's token record (record 1) is a list of line records and a
`$00` byte:

| Field | Bytes | |
|---|---|---|
| length | 1 | the whole record, this byte to its `$00`: the next record is at this one + length |
| line number | 2 | 0 = none |
| source line | 2 | the line of the `.bas` file (1 is the first), for error jumps and breakpoints |
| flags | 1 | bit 0 breakpoint (the editor's, never in a file: the runtime sets it in its copy before a run and at each Continue, from the editor's list, DECISIONS V97), bit 1 a label line, bits 4-7 the indentation / 2 |
| tokens | n | at most 248 |
| end | 1 | `$00` |

A line with more than 248 token bytes is the error *Line too long* (the
plan's 250 would not fit a one-byte length with the six header bytes).
Blank source lines have no record: they are the gaps between the source
line numbers. Offsets in this document ("the offset of a token") count
from the start of record 1; format 1 programs are below 64 KB of tokens.

## 5. Prepare

Prepare runs after tokenizing; Check is tokenize + prepare. It changes no
token's length, so every offset stays valid. It:

### 5.1 Matches blocks and fills the `$0B` offsets

Each offset is the offset of the partner's token (its first byte):

| After | Points at |
|---|---|
| `IF` (a block: `THEN` ends its line, or only a comment follows) | its first `ELSEIF`, `ELSE` or `END IF` |
| `IF` (one line) | its `ELSE` on that line, or the line's `$00` |
| `ELSEIF` | the next `ELSEIF`, `ELSE` or `END IF` |
| `ELSE` | `END IF`; in a one-line `IF`, the line's `$00` |
| `WHILE` / `WEND` | each other |
| `REPEAT` / `UNTIL` | each other |
| `DO` / `LOOP` | each other |
| `FOR` / `NEXT` | each other (`NEXT j, i` points at the inner `FOR`; both `FOR`s at it) |
| `SELECT CASE`, `CASE` | the first or next `CASE`, `CASE ELSE` or `END SELECT` |
| `CASE ELSE` | `END SELECT` |
| `SUB` / `FUNCTION` | `END SUB` / `END FUNCTION` |
| `TRY` | `CATCH`, or `END TRY` |
| `CATCH` | `END TRY` |
| `EXIT FOR`, `EXIT WHILE`, `EXIT DO`, `EXIT REPEAT` | the innermost such loop's `NEXT`, `WEND`, `LOOP`, `UNTIL` |
| `EXIT SUB`, `EXIT FUNCTION` | the procedure's `END SUB`, `END FUNCTION` |
| `DIALOG` | `END DIALOG` |

`ELSE` binds to the nearest one-line `IF` on its line that has none yet.
A one-line `IF` may not hold other blocks, except `FOR` and `NEXT`, which
there keep offset 0: they are matched at run time, V2's way (`IF x THEN
NEXT I`). Blocks may not cross a procedure's edge; `SUB` and `FUNCTION`
are not nested. `MENU` is not a block (`END MENU` is optional).

### 5.2 Procedures and their local slots

For each `SUB` and `FUNCTION` the procedure table (record 0) gets its
symbol, the offsets of its `SUB`/`FUNCTION` and `END` tokens, and its
**frame**: a FUNCTION's result first (slot 0, named as the function),
then the parameters in order, then the `LOCAL` names in order. Inside the
procedure (from its `SUB` token to its `END SUB`), every `$06` that names
a frame entry is rewritten to `$8000` + its slot. The result's name
followed by `(` stays a call (recursion). `SHARED` names stay globals; so
does any name the procedure does not make local.

### 5.3 Resolves names and builds the indexes

- Each `$08` gets its target: a label's line record (its offset), a
  procedure's `SUB`/`FUNCTION` token.
- The symbol table gets each name's kind (bits: 1 variable, 2 array, 4
  `CONST`, 8 SUB, 16 FUNCTION, 32 label, 64 built-in constant) and type (0
  float, 1 integer, 2 string). An unsuffixed name is an integer after
  `OPTION INTEGER` (anywhere in the program) or when `DEFINT` covers its
  first letter. A name used with `(` that is not a FUNCTION is an array
  (V2's arrays without `DIM` included).
- The line index (record 2): every numbered line, sorted.
- The DATA index (record 3): the offset of every `$0A`, in order.

### 5.4 Reports structural errors

With the source line (`file:line: message` from `vbtokens.py check`):

| Message | |
|---|---|
| `X without Y` | `NEXT without FOR`, `WEND without WHILE`, `UNTIL without REPEAT`, `LOOP without DO`, `END IF without IF`, `ELSE without IF`, `ELSEIF without IF`, `CASE without SELECT CASE`, `END SELECT without SELECT CASE`, `CATCH without TRY`, `END TRY without TRY`, `END SUB without SUB` ... |
| `Y missing for X in line N` | at the line where it had to come (or the last line): `END IF missing for IF in line 40` |
| `NEXT j does not match FOR i in line N` | |
| `Two ELSE parts for IF in line N`, `ELSEIF after ELSE ...`, `Two CATCH parts ...`, `CASE after CASE ELSE`, `CASE expected after SELECT CASE in line N` | |
| `THEN missing after IF`, `THEN missing after ELSEIF` | |
| `X inside a one-line IF` | a block word there (not `FOR`, `NEXT`, `EXIT`) |
| `SUB B inside SUB A (line N)`, `SUB A defined twice (lines M and N)`, `Name expected after SUB`, `Parameter name expected`, `Parameter p given twice` | |
| `EXIT FOR outside FOR` ... `EXIT SUB outside SUB` | |
| `LOCAL outside a SUB or FUNCTION`, `SHARED outside ...`, `x is already local in SUB A`, `x is LOCAL and SHARED` | |
| `RETURN with a value outside a FUNCTION` | |
| `Undefined label X`, `Undefined line N`, `Undefined SUB X` | `ON ERROR GOTO 0` is allowed |
| `Label X defined twice (lines M and N)`, `Line number N used twice (lines M and N)`, `X is both a label and a SUB` | |
| `Cannot assign to constant X`, `Constant X defined twice`, `X is a built-in constant` | |

The tokenizer's own errors: `Unexpected character`, `Name too long`,
`Number too big`, `Number too long`, `Line number expected`, `Line number
out of range`, `String too long`, `Line too long`.

## 6. Detokenizing: the canonical form

`detok` writes each line record back as text:

- keywords in upper case, compounds with one blank; names as the symbol
  table spells them (their first appearance in the source);
- one blank between words and around binary operators; none after `(`,
  `#` or a unary `-`/`+`, none before `)`, `,`, `;`, `:`; one after `,`,
  `;` and `:`; none between a name or a function keyword and its `(`;
  `DEFINT A-Z` keeps `-` tight;
- line number, one blank, two blanks per indentation level, the tokens;
- integers: decimal as a number; hexadecimal `$` and 2 digits below
  `$100`, else 4 (`$0801`); binary `%` and 8 digits below 256, else 16;
  floats as spelled; strings with quotes doubled;
- comments and `DATA` items byte for byte;
- a blank line for each gap in the source line numbers.

So the canonical form drops the case of keywords, crunched or extra
blanks, comment alignment, and the digit count of `$` and `%` numbers.

### Round-trip guarantees

| | Guarantee | Checked by |
|---|---|---|
| G1 | `tok(detok(T)) == T` byte for byte, records 0-3, for the tokenizer's output and for the prepared program | gate `vb_spec` (corpus, examples, fuzz) |
| G2 | `detok(tok(S))` is the expected canonical form (the file itself, or `NAME.canon` beside it) and `canon(canon(S)) == canon(S)`; `tok(canon(S)) == tok(S)` | gate `vb_spec` |
| G3 | the X16 tokenizer gives the same bytes, records 0-3, and the same first error message | gate `vb_tok` (phase 2: 893 programs) |
| G4 | `run(S)` and `run(detok(tok(S)))` log the same | gate `vb_core` (phase 1) |

## 7. The program document's records

The prepared program is four records.

**Record 0: header, symbol table, procedure table**

| Offset | Bytes | |
|---|---|---|
| 0 | 2 | `VB` |
| 2 | 1 | the token format (1) |
| 3 | 1 | the runtime version it needs (1) |
| 4 | 2 | symbols |
| 6 | 2 | procedures |
| 8 | 2 | line records |
| 10 | 2 | the size of record 1 |
| 12 | 2 | entries of the line index |
| 14 | 2 | DATA items |
| 16 | 1 | bit 0 `OPTION INTEGER`; bit 7 prepared |
| 17 | 4 | `DEFINT` letters (bit n = letter A + n) |
| 21 | 3 | 0 |
| 24 | | the symbols, then the procedures |

A symbol: kind (1), type (1), target (3: a label's or procedure's
offset), value (2: a built-in constant's), name length (1), the name.
A procedure: symbol (2), the offset of its `SUB`/`FUNCTION` token (2), of
its `END` token (2), parameters (1), frame entries (1), flags (1: bit 0
FUNCTION), then each frame entry: symbol (2), flags (1: bit 0 `BYREF`,
bit 1 array, bit 2 parameter, bit 3 the result).

**Record 1:** the line records (section 4). **Record 2:** the line index,
4 bytes an entry: line number (2), the record's offset (2), by number.
**Record 3:** the DATA index, the offset (2) of each item; pictures
(`PICTURE$(DATA)`) are made from it at run time.

### 7.1 The file

`Name.cvt`: a GEOS VLIR file in CVT format (docs/APPFORMAT.md), GEOS type
`APPL_DATA`, class `VeraBASIC   V1.0`, parent class `VBRun       V1.0`
(VeraBASIC Run opens it), Veranda's default icon in format 1, records 0-3
as above (an empty record is 0/`$FF` in the record table). The GEOS name
inside is the file name's first 16 characters (without `.cvt`); the FAT
name may be up to 63 (DECISIONS V82). `vbasic.py build` writes it,
`vbasic.py list` reads it back to source; `vpack.py --list` shows it. A
standalone application carries the same four records after Run's
(section 7.3).

**Opening it.** A double click in the shell on a GEOS document (type
`APPL_DATA`) starts the application of its parent class: the info block's
bytes 117-136, of which the shell compares the first 12 characters (the
name, any version) with the classes of the applications in the folder
shown, `/VERANDA/APPS`, `/VERANDA` and the top folder (`FindFTypes`), and
starts the first with `GetFile(app, ST_LD_DATA, 0, document, 0)`: the
document's whole name in `dataLongName` (DECISIONS V87). A `.bas` file
opens with VeraBASIC Run by its extension (Run's `documents = BAS`, V48).

### 7.2 The X16 tokenizer's limits

VeraBASIC Run tokenizes and prepares a `.bas` file itself (DECISIONS V87).
Where its memory ends, it reports an error the PC would not:

| Limit | Error |
|---|---|
| 64 KB of source (65,280 bytes) | *The program is too big* |
| a source line of 255 characters (the PC: any length, if its tokens fit 248 bytes) | *Line too long* |
| 512 names, 7.9 KB of their spellings | *Too many names* |
| 128 procedures, 100 frame entries (parameters and locals) a procedure, 24 blocks open at once, 48 `EXIT`s waiting for their block's end, 16 one-line `IF`s a line, 128 statements a line | *Program too big* |
| record 1 in 8 banks (64 KB), 2,048 numbered lines, 4,096 `DATA` items | *Program too big* |

The PC's checks of names and line numbers in use (*Undefined line*,
*Undefined label*, *Undefined SUB*) cover the first 2,730 uses on the
X16; a program with more is still checked by Run when it runs.

### 7.3 A made application

*File > Make application...* in the editor and `vbasic.py app` (DECISIONS
V99) write the same file: VeraBASIC Run's (`VRND`, API 6, banked
overlays) with these changes.

| Where | What |
|---|---|
| directory entry 3-18 | the GEOS name: `APP NAME`'s first 16 characters, `$A0` padded |
| directory entry 23-27, 28-29 | the date of the making; the blocks |
| CVT 96, 97-224 | the tile: `APP TILE`'s colour, `TILE DATA`'s 32 rows (else Run's) |
| info 77-96 | the class: `APP CLASS` (default: the name's first 12 characters) padded to 12, `V`, `APP VERSION` (`1.0`) |
| info 97-116 | `APP AUTHOR` |
| info 143 | flags: 1 (banked) + 2 (a tile) + 4 with `APP STAY` |
| info 144-159 | `APP DOCUMENTS`: four slots of 4, upper case, blank padded |
| info 160-255 | `APP DESCRIPTION` |
| records 0-11 | VeraBASIC Run's, as they are |
| records 12 on | the program, 8191 bytes a record (a banked overlay's most) |

The program's bytes, cut into those records, are an 80-byte header and
the program document's four records one after the other:

| Offset | Bytes | |
|---|---|---|
| 0 | 4 | `VBAP` |
| 4 | 1 | the form of these records (1); a later one: *Made by a newer VeraBASIC* |
| 5 | 1 | the token format (record 0's byte 2) |
| 6 | 8 | the sizes of records 0-3 |
| 14 | 2 | 0 |
| 16 | 64 | the name (`APP NAME`), 0-terminated |

VeraBASIC Run, started, looks for record 12 (`LoadOverlay`): with `VBAP`
there it is an application. It copies the four records out of its own
banks into runs as the tokenizer leaves them, loads the program as from a
document, names its first menu and its window after the program, leaves
out *Open program...*, and runs it; started with a document (one of its
`APP DOCUMENTS` extensions, `ST_LD_DATA`), `DOCUMENT$` is the document's
whole name (`dataLongName`) and the current folder the document's.

## 8. `tokens.inc`

Generated; included by the X16 tokenizer, detokenizer and dispatcher.

- `TAG_*`: the tags of section 3. `TK_name` (first page) and `TX_name`
  (second page, after `TAG_EXT`): the keywords (`$` in a name is `_S`,
  `%` `_I`, a blank `_`: `TK_LEFT_S`, `TK_END_IF`). `VBC_*`: the
  predefined constants. `VBO_*`: the overlays (`core` 0, `gfx`, `file`,
  `dlg`, `snd`, `msg`, `tok`). `VBF_*`, `VBX_*`: the flag bits.
- With `VB_LEXTABLES` defined (VeraBASIC Run's lexer, overlay 2): the
  keyword buckets, the two-character operators, the compounds, the flag
  tables of both pages and `vb_procarg` (the statements with a procedure
  argument and its position); the macro `vb_consts_table` is the
  predefined constants (length, name, value), for prepare's overlay.
- With `VB_TABLES` defined (all the tables, 5.6 KB):
  - `vb_kw_len`: for word length L = 1 .. `VB_KW_MAXLEN`, the address of
    that bucket and its count (3 bytes); a bucket is sorted, each entry L
    upper-case bytes and the token (tk, 0 or `$FF`, nn): the lexer reads
    a whole word, upper-cases it and searches its bucket;
  - `vb_ops2`: `<=`, `<>`, `>=` and their tokens;
  - `vb_compound`: first word's token, second's, the compound's (2 bytes
    each), ended by 0;
  - per page (`VB_PAGE1_FIRST` `$80`, 127 entries; `VB_PAGE2_FIRST` `$01`,
    255): `vb_flags`, `vb_xflags`, `vb_ovl`, `vb_ent` (the dispatch: the
    overlay and the entry number, `$FF` for a word or an operator),
    `vb_value` (the value of `PAPER`, `INK`, `SELECT`, `TITLE`, `DATA` in
    an expression), `vb_name` (offset and length in `vb_names`, for
    detokenizing).
- `vb_entries_X` macros: each overlay's entry addresses in dispatch order
  (`vbs_PRINT`, `vbf_LEFT_S` ...), so the overlay's jump table and the
  dispatch table cannot disagree; `VB_ENTRIES_X` is the count.

The first-page bucket search is a whole-word match, not a character trie:
names are whole words with a suffix, so the X16 lexer reads the word
first (a deliberate change from the plan's "keyword trie").

## 9. The help files

`/VERANDA/HELP/*.HLP`: plain Latin-1 text, LF, lines of at most 78
characters, read by the editor's help viewer (phase 5) and readable in
Veranda Edit.

- `= Name` starts a page (to the next `=` line); F1 opens the page named
  as the keyword under the cursor. The first page is `= Contents`.
- `@Name` links to a page (a name of letters, digits, `_`, `$`, `%`);
  `@{Two words}` links to a page whose name has other characters.
- A line that starts with two blanks is code (shown in the 8 x 8 font,
  as written).
- Other lines are text; a blank line ends a paragraph.

`KEYWORDS.HLP` (generated): the contents, a page a group (its
introduction and its keywords' links), and a page a keyword or constant:
the syntax line, the help text, the value (constants), the example as
code, *See also* links.

## 10. What the generator checks

`vbgen.py` stops with every problem listed when: a keyword or constant has
no syntax line, no help text or no example; a name or a token appears
twice, a token is outside its page or retired; a compound's words are not
keywords; a kind, overlay, group, flag or argument code is unknown; a
statement or function has no overlay, a word has one; a kernel name is in
neither `api/veranda.api` nor `sdk/lib/*.h` (`VERA:`, `ROM:` and `new:`
are allowed); a `see` names nothing; a constant's value differs from the
API's (`api=`) or `theme.h`'s (`theme=`); two keywords make one ca65
name; a hand-written page of `docs/vbasic/manual` names a `{KEYWORD}` the
table does not have.

## 11. A worked example

```basic
10 n% = $FF
SUB Greet(who$)
  IF who$ = "" THEN EXIT SUB
  PRINT "Hi "; who$
END SUB
Greet "Robin"
```

Record 1 (`vbtokens.py dump`), one line record a row:

```
0000  0E 0A00 0100 00 | 06 0000 3D 02 FF00 | 00              10 n% = $FF
000E  16 0000 0200 00 | AC 0B 5100 08 0100 140000 28 06 0080 29 | 00
                        SUB [->END SUB] Greet(local 0)
0024  16 0000 0300 10 | 90 0B 3900 06 0080 3D 05 00 91 AA 0B 5100 | 00
                        IF [->$00 of this line] who$ = "" THEN EXIT SUB [->END SUB]
003A  11 0000 0400 10 | 80 05 03 48 69 20 3B 06 0080 | 00
                        PRINT "Hi " ; who$
004B  08 0000 0500 00 | AD | 00                         END SUB (at $0051)
0053  14 0000 0600 00 | 08 0100 140000 05 05 52 6F 62 69 6E | 00
                        Greet [->$0014] "Robin"
0067  00                                                the end of the program
```

`Greet` is symbol 1 (a SUB, target `$0014`); `who$` is the SUB's frame
slot 0 (`06 00 80`); the line index holds line 10 at offset 0.
