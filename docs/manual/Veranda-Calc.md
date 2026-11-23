# Veranda Calc

Veranda Calc is a **spreadsheet**. It is Commander Calc, the X16
spreadsheet, built as a Veranda program. It reads and writes Excel
(`.XLSX`) and CSV files, and reads LibreOffice (`.ODS`) files, all on the
X16. Version 1.1. MIT licence, Copyright (c) 2026 Marcin Spoczynski.

Commander Calc has its own, longer manual in its repository. This page
covers what you need on Veranda.

## Start it

- Double-click **Veranda Calc** in `/VERANDA/APPS`.
- Double-click a workbook: `.X16S` files open; `.XLSX`, `.ODS` and
  `.CSV` files are imported.

## The window

The menu bar; a title band with the workbook's name ("Untitled" until
you save); the formula bar; the grid with grey row and column headers;
sheet tabs at the bottom; and a status bar with READY, EDIT or MODIF,
the cell, and the memory free.

## Features

- **16 worksheets** of 65,535 rows by 256 columns (A to IV), up to
  16,384 cells a sheet.
- Numbers, text, true and false, dates, formulas, errors.
- **Formulas** with 14 functions: SUM, AVERAGE, MIN, MAX, COUNT, IF,
  AND, OR, NOT, ABS, ROUND, INT, MOD, LEN. Operators `+ - * / ^ = <> <
  <= > >=`. Absolute references (`$A$1`) and references to other sheets
  (`Q1!B5`). A circular reference shows `#CYCLE!`. Automatic or manual
  recalculation.
- **Blocks:** select a block (Ctrl+A, then move; or drag with the
  mouse); copy, paste, clear and sort it. Pasted formulas are adjusted.
- Insert and delete rows and columns; column widths from 3 to 40;
  frozen headings; bold; borders and underlines.
- **Find and replace.**
- **Charts:** bars, line or pie of the cursor's column (up to 16
  values), labelled from the column to its left. On Veranda they are
  black and white with patterns. Press **S** in a chart to save
  `CHART.BMP` (640 x 464).
- **The clipboard:** Copy also puts the cells on Veranda's clipboard as
  text (a tab between cells, a new line after each row). Paste takes
  text from another program: lines become rows, tabs separate cells.
- **Desk accessories** over the workbook: Veranda Calc menu > Desk
  accessory...

## Menus

| Menu | Items |
|---|---|
| Veranda Calc | About Veranda Calc..., Desk accessory... |
| File | New (F1), Open... (F3), Save (F4), Save as... (F6), Import... (F7), Export... (F8), Quit (F9) |
| Edit | Edit cell (F2), Select (Ctrl+A), Copy (Ctrl+C), Paste (Ctrl+V), Undo (F5), Clear (Del), Find... (Ctrl+F), Replace... |
| Layout | Insert row, Delete row, Insert column, Delete column, Column width..., Bold (Ctrl+B), Border, Underline, Freeze |
| Data | Sort up, Sort down, Undo sort, Recalc now, Auto recalc |
| Chart | Bars, Line, Pie |
| Sheet | Next, Previous, Add..., Rename..., Delete |

## Keys

| Key | Action |
|---|---|
| Arrows | move a cell |
| Return | down a row |
| Tab, Shift+Tab | right, left a column |
| PgUp, PgDn | a screen up, down |
| Home | column A of this row |
| Shift+Home | cell A1 |
| End | column IV of this row |
| F1 | New |
| F2 | Edit the cell |
| F3 | Open |
| F4 | Save |
| F5 | Undo |
| F6 | Save as |
| F7 | Import |
| F8 | Export |
| F9 | Quit (asks before it drops changes) |
| F11 | Paste |
| Ctrl+A | start or drop a block |
| Ctrl+B | Bold |
| Ctrl+C, Ctrl+V | Copy, Paste |
| Ctrl+F | Find |
| Backspace, Delete | clear the cell or the block |
| Any other key | start typing a new value in the cell |
| Right mouse button | edit the cell under the pointer |

**While you type in a cell:** Left and Right move in the text; Home and
End go to its start and end; Backspace and Delete delete; Return or
Down stores and moves down; Up stores and moves up; Tab and Shift+Tab
store and move right or left; **Esc** drops the entry. At most 80
characters can be typed in a cell.

**Careful:** some Ctrl keys share a code with other keys. **Ctrl+P
quits** (it asks first if there are changes). Ctrl+T and Ctrl+Y clear
the cell.

**The mouse:** a click moves to a cell; dragging selects a block; the
wheel scrolls; a click on a tab shows that sheet.

## Files

| Format | Open | Save |
|---|---|---|
| `.X16S` (Veranda Calc's own, checked with a CRC) | Open | Save, Save as |
| `.XLSX` | Import | Export |
| `.ODS` | Import | (no) |
| `.CSV` | Import | Export |

Export writes `.XLSX` when the name ends in `.XLSX`, otherwise CSV.
Save as adds `.X16S` to a name without an extension. Saving is safe:
the file is written, read back and checked, then it replaces the old
one. `.X16S` opens about three times faster than `.XLSX`.

The Open box starts in the folder Veranda Calc works in: `/DOCUMENTS`
at first, then the folder of the last file. [Dex](Dex.md) can export
your addresses as a CSV file that Veranda Calc opens.

## Limits

- About 320 KB for workbooks on a 512 KB machine. The status bar shows
  the bytes free. Memory is used in bands of 256 rows: keep your data
  close together.
- Large workbooks are slow: a sheet of 2,400 cells takes about 40
  seconds to open and 30 to save.
- An XLSX import is limited to about 3,000 cells. An import that runs
  out of memory stops, keeps what it read, and says so.
- Numbers have about 9 significant digits.
- Number formats and alignment are kept from imported files, but you
  cannot set them.
- Undo is one level, one cell. Undo sort works once, on the same
  sheet.
- `.ODS` is read only.
- If the status line shows `STACK!`, save under a new name and start
  Veranda Calc again.
