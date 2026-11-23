# 3b. Veranda extensions, part 2

This chapter covers the rest of what makes a VeraBASIC program a Veranda
program: files with long names and folders, dialog boxes (the system's
Open and Save dialog among them), the clipboard, pictures, icons, tiles
and sprites (VeraBASIC Run since DECISIONS V90). [Part 1](extensions.md)
has the program model, events, windows, menus, graphics, text, colour,
the mouse, the keys, time and sound.

Each statement has its syntax, a listing you can run, and the kernel call
it maps to (docs/API.md). Every listing here is run by gate `vb_files` on
the X16 and in the reference interpreter, on the emulator's host folder
and on an SD card image; what a listing writes must be the reference's
byte for byte, and its boxes are answered with the real mouse and keys
(the `mouse` block after it).

The complete example programs are in [../examples](../examples): *Notes*
(Open and Save with long names, the clipboard), *Dice* (icons, a sprite,
sounds), *Address book* (files, a `DIALOG`) and *Tiles* (a page of
tiles). Gate `vb_files` runs each of them with a mouse script.

## 1. Files

| Statement / function | Maps to |
|---|---|
| `OPEN #h, name$, mode$` | `FOpen`: mode `"r"` read, `"w"` write (a new file, or the old one replaced), `"m"` read and write (the file must be there) |
| `CLOSE #h [, #h] ...` / `CLOSE` | `FClose`, what is written out first; no number: every file |
| `PRINT #h, ...` | as `PRINT`, to the file (a line ends with LF) |
| `INPUT #h, v [, v] ...` | a line's fields (as `INPUT` takes them: commas, quotes), more lines as needed |
| `LINE INPUT #h, v$` | a line: to LF, CR or CR LF (255 characters at most) |
| `GET #h, v$, n` / `PUT #h, s$` | up to n bytes / the bytes of s$, nothing added |
| `SEEK #h, position` | `FSeek`: the next byte read or written (0 is the first) |
| `LOC(h)`, `LOF(h)` | the position, the size (24 bits: 16 MB) |
| `EOF(h)` | -1 at the end (a file opened `"w"`: always), else 0 |

A handle is a number from 1 to 255 of the program's; at most **3 files are
open at once** (the kernel's streams, V68), a fourth `OPEN` is error 51.
Names are the card's: **long names up to 63 characters**, in the current
folder; a name may hold a folder (`"Lists/Birds.txt"`, from the current
folder, or `"/DOCUMENTS/Birds.txt"`, from the top), 64 characters in
all. A name may not hold a comma (CMDR-DOS's `OPEN` reads `name,S,W`).
(On the emulator's host folder alone, not on an SD card or the X16
itself: a *new* file by a name from the top with a folder in it,
`"/DOCUMENTS/New.txt"` written while the current folder is not the top,
is error 50: x16emu's host folder looks for its folder under the current
one. The SD card image is the one to test such names on.)
Each file has a buffer of 256 bytes in the runtime's bank; everything is
written out and closed when the program ends, after an error too.

```basic
' write a file with a long name, read it back
n$ = "Birds seen from the veranda on a morning in spring 2026.txt"
OPEN #1, n$, "w"
PRINT #1, "Robin", 3
PRINT #1, "Wren"; 7
PRINT #1, "Blue tit, two of them"
PRINT "written:"; LOC(1); "bytes"
CLOSE #1
OPEN #1, n$, "r"
PRINT "size:"; LOF(1)
WHILE NOT EOF(1)
  LINE INPUT #1, l$
  PRINT "["; l$; "]"
WEND
CLOSE #1
END
```

`INPUT #` reads whole lines: fields separated by commas, a field in
quotes keeps its commas; when the variables want more fields than the
line has, the next line goes on; fields left over are dropped. A number
that is not one is error 13. `GET #`, `PUT #` and `SEEK` work on bytes.

```basic
' fields, bytes, a position
OPEN #1, "Counts.txt", "w"
PRINT #1, CHR$(34); "Blue, tit"; CHR$(34); ", 12, 3.5"
PRINT #1, "Robin, 4"
PRINT #1, "2.25"
CLOSE #1
OPEN #1, "Counts.txt", "r"
INPUT #1, a$, n, x
INPUT #1, b$, m, y
PRINT a$; n; x; " / "; b$; m; y
CLOSE #1
OPEN #2, "Counts.txt", "m"
SEEK #2, 1
PUT #2, "Gr"
SEEK #2, 0
GET #2, g$, 9
PRINT g$; LOC(2)
CLOSE
END
```

## 2. Folders

| Statement / function | Maps to |
|---|---|
| `KILL name$` | `FDelete` |
| `NAME old$ AS new$` | `FRename` (old must be there, new not: errors 50, 58) |
| `MKDIR path$` / `RMDIR path$` | `MkDir`, `RmDir` (an empty folder only: 57) |
| `CHDIR path$` | `ChDir`: from `/`, or from the current folder; `..` up |
| `CURDIR$` | the current folder's path (`curDirName`, which programs keep, V71) |
| `DIR$(pattern$)`, then `DIR$()` | `DirOpen`, `DirNext`: the names matching (`*` any run, `?` any one; either case), a folder's with `/` after it; `""` at the end |
| `FOLDER$(DOCS)` ... | the card's folders (V71): `DOCS` /DOCUMENTS, `APPS` /VERANDA/APPS, `FONTS` /VERANDA/FONTS, `SYSTEM` /VERANDA, `DATA` /VERANDA/.SYSTEM |
| `DOCUMENT$` | the document a made application was opened with (phase 7); under VeraBASIC Run `""` |

```basic
' a folder of its own: made, listed, emptied, removed
MKDIR "Bird lists"
CHDIR "Bird lists"
PRINT CURDIR$
OPEN #1, "Monday.txt", "w" : PRINT #1, "3 robins" : CLOSE #1
OPEN #1, "Tuesday.txt", "w" : PRINT #1, "a wren" : CLOSE #1
NAME "Tuesday.txt" AS "Tuesday morning.txt"
n = 0
f$ = DIR$("*.txt")
WHILE f$ <> ""
  n = n + 1
  f$ = DIR$()
WEND
PRINT n; "lists"
KILL "Monday.txt"
KILL "Tuesday morning.txt"
CHDIR ".."
RMDIR "Bird lists"
PRINT CURDIR$; " "; FOLDER$(DOCS); " ["; DOCUMENT$; "]"
END
```

## 3. Errors of files

The kernel's errors become the program's, caught by `TRY` as any other;
`ERRFILE` is the kernel's own code (docs/API.md).

| Number | Message | When (`ERRFILE`) |
|---|---|---|
| 50 | File not found | no such file or folder (5) |
| 51 | Too many files | a fourth file open (16) |
| 52 | Bad file number | a handle not 1-255 |
| 53 | File not open | a handle not open |
| 54 | File already open | `OPEN` of a handle open |
| 55 | Bad file mode | not `r`, `w` or `m`; `PRINT #` to a file read, `INPUT #` from one written |
| 56 | Input past end | `INPUT #`, `LINE INPUT #` at the end |
| 57 | Disk error | the DOS's other errors (20 and others): a folder not empty |
| 58 | File exists | `NAME` onto a file there, `MKDIR` of a folder there (15) |
| 59 | Bad picture | a string that is not a picture; a picture too big |
| 60 | Not in a DIALOG | `LABEL`, `FIELD`, `BUTTON`, `END DIALOG` outside one; too many |

```basic
' errors caught
TRY
  OPEN #1, "No such list.txt", "r"
CATCH
  PRINT ERR; ERR$; ERRFILE
END TRY
OPEN #1, "One.txt", "w"
OPEN #2, "Two.txt", "w"
OPEN #3, "Three.txt", "w"
TRY
  OPEN #4, "Four.txt", "w"
CATCH
  PRINT ERR; ERR$; ERRFILE
END TRY
TRY
  LINE INPUT #1, a$
CATCH
  PRINT ERR; ERR$
END TRY
CLOSE
END
```

## 4. Message boxes

| Statement / function | Maps to |
|---|---|
| `MSGBOX text$ [, title$]` | `DoDlgBox`: the text (a `CHR$(10)` starts a new line), the title in bold, OK |
| `ASK(question$)` | `DoDlgBox` with Yes and No (the warning sound): 1 Yes, 0 No |
| `INPUTBOX$(prompt$ [, default$ [, length]])` | `DoDlgBox` with a text field (63 characters at most): its text on OK, `""` on Cancel |

Return is OK (Yes), Esc Cancel (No). The boxes are the kernel's (V15) in
the UI font, centred.

```basic
' a message, a question, a line asked for
MSGBOX "The feeder is full again." + CHR$(10) + "Robins first.", "Bird Watch"
IF ASK("Count the birds now?") THEN PRINT "yes" ELSE PRINT "no"
n$ = INPUTBOX$("Which bird came first?", "Robin", 20)
PRINT "first: "; n$
END
```
```mouse
dialog 1
type \n
dialog 2
type \n
dialog 3
type s\n
pause 60
```

## 5. Dialog boxes of your own

| Statement / function | Maps to |
|---|---|
| `DIALOG x, y, w, h` ... `END DIALOG` | a box at cards x, y, w by h (16 x 6 at least); `END DIALOG` shows it (`DoDlgBox` with a `DB_USR_ROUT` for the fields) |
| `LABEL x, y, text$` | a text at cards x (below 32), y of the box (8 at most) |
| `FIELD x, y, v$, length` | a text field: it starts with v$, and its text goes to v$ when the box closes with OK (4 at most) |
| `BUTTON OK` / `BUTTON CANCEL` | the system's buttons, at the bottom right (none: OK) |
| `DIALOG RESULT` | how the last box closed: 1 OK, 2 Cancel |

A press on a field gives it the keys; Tab goes to the next, Return is OK,
Esc Cancel. The statements between `DIALOG` and `END DIALOG` may be any
(an `IF` around a `FIELD`, a loop of `LABEL`s).

```basic
' a box of two fields
nm$ = "Robin"
tw$ = ""
DIALOG 20, 15, 40, 14
  LABEL 2, 2, "Name:"
  FIELD 10, 2, nm$, 20
  LABEL 2, 5, "Town:"
  FIELD 10, 5, tw$, 20
  BUTTON OK
  BUTTON CANCEL
END DIALOG
IF DIALOG RESULT = 1 THEN PRINT nm$; " of "; tw$ ELSE PRINT "cancelled"
END
```
```mouse
dialog 1
click 250 158
type Lakeside\n
pause 60
```

## 6. Open and Save

| Function | Maps to |
|---|---|
| `FILEOPEN$(title$ [, extension$])` | `vr_file(VRF_OPEN, ...)`: the SDK's Open dialog (V79), the type filter `extension$` (`"TXT"`) on at the start; the name chosen, `""` on Cancel |
| `FILESAVE$(title$, default$)` | `vr_file(VRF_SAVE, ...)`: the Save dialog, the field starting with `default$`; a name of up to 63 characters |

The dialog is the system's own, with long names, folders, a folder
pop-up, New folder and the keys (sdk/lib/vrchoose.h). It opens in
`CURDIR$`; the folder chosen becomes the current one, so the name it
gives goes straight to `OPEN`. (The dialog is C: VeraBASIC Run carries it
in two RAM banks of its own and runs the C library's part of it in the
console font's place, V90.)

```basic
' save a list where the user says, open it again
f$ = FILESAVE$("Save the list as", "A list of the birds at the feeder.txt")
IF f$ = "" THEN END
OPEN #1, f$, "w" : PRINT #1, "Robin" : CLOSE #1
PRINT "saved in "; CURDIR$
g$ = FILEOPEN$("Open a list", "TXT")
IF g$ <> "" THEN OPEN #1, g$, "r" : LINE INPUT #1, l$ : CLOSE #1 : PRINT l$
END
```
```mouse
dialog 1
pause 30
type \n
dialog 2
pause 30
type A
pause 20
type \n
pause 60
```

## 7. The clipboard

| Statement / function | Maps to |
|---|---|
| `CLIPBOARD s$` | the Text Scrap (`scrap_put_text`, V54): plain text, a `CHR$(10)` ends a line (CR in the scrap), as Veranda Edit writes it |
| `CLIPBOARD$` | the Text Scrap's text (`scrap_get_text`): 255 characters at most, a line's end as `CHR$(10)`; `""` when there is none |
| `CLIPBOARD PICTURE x1, y1, x2, y2` | the Photo Scrap (`scrap_put_photo`): the screen's area (x to whole cards) with its cards' colours |

The scraps are GEOS's files in `/VERANDA/.SYSTEM` (or the top folder of a
card without `/VERANDA`), so Veranda Edit, Paint, geoWrite and the
managers paste what a program copies, and the other way round.

```basic
' text to the clipboard and back, a picture of the screen
CLIPBOARD "Two robins" + CHR$(10) + "and a wren"
c$ = CLIPBOARD$
PRINT LEN(c$); ASC(MID$(c$, 11, 1))
CLIPBOARD PICTURE 0, 16, 63, 47
END
```

## 8. Pictures, icons, tiles and sprites

A **picture** is a string: its width in cards, its height in lines, then
the bitmap in GEOS's compacted form (BitmapUp's). `PICTURE$` makes one.

| Statement / function | Maps to |
|---|---|
| `PICTURE$(DATA)` | the next `DATA` items: the width (1-128 pixels), the height (1-160), then a string a row of `#` (ink) and `.` |
| `PICTURE$(file$)` | a text file's rows of `#` and `.` (other lines left out: an application's `tile.txt` is one); the width the longest |
| `BITMAP x, y, picture$` | `WBitmapUp` at x (to a card), y |
| `ICON id, x, y, picture$, sub` | an icon (1-8): drawn; a press on it inverts it, its release there calls the SUB (an `ICON` event) |
| `ICON OFF id` / `ICONS CLEAR` | the icon (all of them) taken away, its place cleared |
| `TILE x, y, name$ [, colour]` | an application's tile, as the shell shows it (V77; the SDK's `vr_tile`): its own (the tile block of its file), else its GEOS icon on a chrome tile, on 4 x 4 cards of its colour; the file `name$.cvt` looked for in the current folder, /VERANDA/APPS, /VERANDA, the top |
| `SPRITE n, picture$` | `DrawSprite`: sprite n (2-7) takes the picture's top left 24 x 21 (512 bytes of picture at most) |
| `SPRITE n AT x, y` / `SPRITE n ON` / `SPRITE n OFF` | `WPosSprite`, `EnablSprite`, `DisablSprite` |

Sprites 0 and 1 are the pointer's and the text cursor's. The program's
sprites go off when it ends; a dialog box hides them while it is up.
Icons are the runtime's own (the kernel's `DoIcons` table would have to
stay in main RAM): they work with `WINDOW USE`'s origin like the drawing.

```basic
' a picture from DATA, drawn, an icon, a sprite, a tile
OPTION INTEGER
WINDOW #1, 4, 4, 60, 30, "Pictures"
WINDOW USE #1
ball$ = PICTURE$(DATA)
DATA 8, 8, "..####..", ".######.", "##.##.##", "########"
DATA "#.####.#", "##....##", ".######.", "..####.."
PRINT LEN(ball$); ASC(ball$); ASC(MID$(ball$, 2, 1))
BITMAP 16, 16, ball$
ICON 1, 48, 16, ball$, Pressed
SPRITE 2, ball$
SPRITE 2 AT 120, 40
SPRITE 2 ON
TILE 12, 2, "AUTOSTART"
WAIT EVENTS
SUB Pressed
  PRINT "pressed"
  SPRITE 2 OFF
  ICONS CLEAR
  END
END SUB
```
```mouse
ready
click 84 68
pause 60
```

## 9. Sizes

VeraBASIC Run carries part 2 in two banked overlays of assembly (8:
dialogs, icons, sprites, tiles, the clipboard's side; 9: files, folders,
pictures) and two RAM banks of C (the SDK's Open and Save dialog, the
scraps, the tile), 11 overlays in all. Main RAM gained nothing for it:
the overlays' banks are loaded from overlay 1 now, which gave back more
than the 6 bytes of state part 2 keeps there.
