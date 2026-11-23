# Programming Veranda

A guide to writing Veranda applications in C. It assumes you know C and
have built the template (see `README.md` in this folder); it does not
assume you know GEOS. Every call is listed in `API.md`, the reference
generated from the API table; this guide explains how the calls fit
together.

Every example below is a complete program. `tools/gate_guide.sh` in the
Veranda tree builds each one against the installed SDK and runs it in the
emulator, so they stay correct. To try one, put it in a copy of
`template/c` as `main.c` and run `make run`.

## 1. How an application runs

An application is not a loop of its own. Veranda loads it at `$0801`,
calls `main()`, and `main()` sets things up and **returns**. From then on
Veranda's main loop owns the machine and calls back into the application
when something happens:

| Event | Vector or table |
|---|---|
| every pass of the main loop | `appMain` |
| a key | `keyVector` (the key in `keyData`) |
| a menu item chosen | the item's routine in the menu table |
| an icon clicked | the icon's routine in the icon table |
| a click elsewhere | `otherPressVec` (presses and releases; `mouseData` bit 7 set: up) |
| the pointer leaves a region | `mouseFaultVec` |
| a timer | a process (section 7) |
| every frame, in the interrupt | `vr_set_irq` (section 8) |

A vector holds the address of a C function `void f(void)`; `VR_FN(f)`
(from `vr.h`) gives it the right type. Callbacks run between the
application's other C code, never in the middle of it, so they may call
anything.

```c
/* example: hello */
#include <veranda.h>
#include <vr.h>

static unsigned int passes;

static void tick(void)
{
    if (++passes == 100) {
        WPutString("100 passes of the main loop", 240, 280);
        LogText("GUIDE hello OK");
        appMain = 0;
    }
}

int main(void)
{
    SetPattern(0);                      /* paper */
    WRectangle(0, 0, 639, 479);
    WFrameRectangle(0xFF, 200, 180, 440, 300);
    WPutString("Hello, Veranda", 270, 244);
    appMain = VR_FN(tick);
    return 0;                           /* the main loop takes over */
}
```

`LogText` writes to the emulator's console and does nothing on hardware;
the examples use it to report that they ran.

To quit, call `EnterDeskTop()` (back to the shell) or `exit()`, which
does the same. To leave Veranda for BASIC, `ToBASIC` with `r1 =
TOBASIC_KEEP` keeps it in memory (the resident core and the kernel banks
stay above MEMTOP, `$8800`; `SYS 35328` or RBOOT from BASIC goes back to
the desktop, in the folder the shell showed; the application itself is not
resumed); with any other `r1` it frees everything. Its argument is a
command typed into BASIC, or 0.

## 2. The screen and drawing

The screen is 640x480 at one bit a pixel; `SetVideoMode` also offers
640x240 and 320x240, and an application's header names the mode it wants
(`mode` in `app.hdr`). `screenWidth` and `screenHeight` hold the current
size.

Drawing calls come in two forms. The **classic** GEOS calls
(`Rectangle`, `PutString`, `HorizontalLine` ...) take a byte for y and
reach only the top 256 rows. Each has a **wide** twin with a `W` in front
(`WRectangle`, `WPutString` ...) that takes a full word for y. In C,
use the wide calls.

- **Patterns.** `SetPattern(n)` picks one of 34 fill patterns for
  `WRectangle`: 0 is paper (white), 1 is ink (black), and the rest are
  greys and textures.
- **Frames and inversion.** `WFrameRectangle(bits, ...)` draws an outline
  with a line pattern (`0xFF` solid). `WInvertRectangle` flips the pixels:
  menus and icons use it to show a selection.
- **Text in cells (API 2).** `PutCards(text, font, x, count, y, flags)`
  draws characters of a fixed 8 x 8 font into whole cards (x in cards,
  any row y): about 35 us a character, a full 80 x 60 screen in 0.17 s.
  The font is the application's own (8 bytes a glyph, glyph c at
  `font + 8 * c`, below `$A000`); flags 1 reverse, 2 bold.
- **Text.** `WPutString(s, x, y)` draws at baseline `y` in the current
  font, from the system font up; `currentMode` holds the style bits
  (`SET_BOLD`, `SET_UNDERLINE` ...). Load another font with
  `LoadCharSet`.
- **Two screens.** Veranda keeps a back screen. `dispBufferOn` says where
  drawing goes: `ST_WR_FORE`, `ST_WR_BACK`, or both, which is the
  default. Menus and dialog boxes restore what they covered from the back
  screen, so anything drawn to both screens survives them. To draw a
  temporary picture, such as a rubber band, draw it to the foreground
  only and take it away by copying back from the back screen.
- **Colour.** `SetColors(paper, ink)` sets the two colours, `$0RGB` each;
  `$FFFF` leaves one as it is, so `SetColors(0xFFFF, ink)` changes the
  ink alone. Every application starts in white paper and black ink.

## 3. Menus

A menu is a table in GEOS's layout. cc65 does not pad structs, so a C
struct describes it exactly:

```c
/* example: menus */
#include <veranda.h>
#include <vr.h>

struct item  { const char *text; unsigned char type; void *p; };
struct menu1 { unsigned char top, bottom; unsigned int left, right;
               unsigned char flags; struct item i[1]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right;
               unsigned char flags; struct item i[2]; };

static void about(void)
{
    GotoFirstMenu();                    /* close the open sub menu */
    WPutString("Veranda guide, menus", 220, 240);
}

static void quit(void)
{
    EnterDeskTop();
}

/* the sub menu: two items, one under the other (VERTICAL) */
static struct menu2 file = { 14, 14 + 2 * 14, 0, 60, VERTICAL | 2, {
    { "about", MENU_ACTION, about },
    { "quit",  MENU_ACTION, quit },
} };

/* the menu bar: one item that opens the sub menu */
static struct menu1 bar = { 0, 14, 0, 30, HORIZONTAL | UN_CONSTRAINED | 1, {
    { "file", SUB_MENU, &file },
} };

int main(void)
{
    DoMenu(&bar, 0);
    LogText("GUIDE menus OK");
    return 0;
}
```

- **The rectangle.** `top`, `bottom`, `left` and `right` place the menu.
  The flags byte holds the orientation (`HORIZONTAL` or `VERTICAL`), the
  pointer constraint, and the item count.
- **Item types.** `MENU_ACTION` calls the routine. `SUB_MENU` opens the
  menu it points to. `DYN_SUB_MENU` calls a routine that returns the
  sub menu's address in `r0`.
- **Closing.** After an action the menu stays open until the routine
  calls `GotoFirstMenu()` (back to the bar), `ReDoMenu()` (the same menu
  again) or `DoPreviousMenu()`.
- **Menus lower down.** For a menu below row 255, set `WIDE_MENU` in the
  flags byte and add the high bytes of top and bottom after it; the items
  then start at offset 9.

## 4. Icons

An icon is a picture with a routine. The picture is a GEOS compacted
bitmap: a count byte from 1 to 127 means "repeat the next byte that many
times", and 128 + n means "n bytes follow as they are". The table gives
each picture's position in cards (8 pixels) across and in pixels down:

```c
/* example: icons */
#include <veranda.h>
#include <vr.h>

/* a 3-card (24 pixel) wide, 16 row high black square: 48 bytes of $FF */
static const unsigned char black[] = { 48, 0xFF };

struct icon   { const void *pic; unsigned char x, y, w, h; void *f; };
struct icons1 { unsigned char n; unsigned int mx; unsigned char my;
                struct icon i[1]; };

static void clicked(void)
{
    WPutString("clicked", 300, 160);
}

static struct icons1 icons = { 1, 320, 120, {
    { black, 40, 100, 3, 16, clicked },     /* x 40 cards = 320 pixels */
} };

int main(void)
{
    iconSelFlg = ST_FLASH;              /* flash the icon when it is clicked */
    DoIcons(&icons);
    LogText("GUIDE icons OK");
    return 0;
}
```

- **The header.** It gives the icon count and the pointer's start
  position (`mx`, `my`).
- **The routine.** It gets the icon's number in `r0L`.
- **Icons lower down.** For icons below row 255, set `WIDE_ICONS` in the
  count byte: the header grows to 5 bytes (y a word) and each entry to 10
  bytes, with the high bytes of y and height last.

## 5. Dialog boxes

`DoDlgBox(table)` opens a box, runs it until one of its buttons closes
it, puts back what it covered and **returns** the button's number (`OK`,
`CANCEL`, `YES`, `NO` ...). Unlike everything else, it waits. The table is
a list of commands:

```c
/* example: dialog */
#include <veranda.h>
#include <vr.h>

struct askdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;         /* DBVARSTR: text at r5 */
    unsigned char t2, x2, y2, reg2, max;    /* DBGETSTRING: input into r6 */
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};

static const struct askdlg ask = {
    DEF_DB_POS | 1,                         /* the default box, shadow 1 */
    DBVARSTR,    TXT_LN_X, TXT_LN_2_Y, 0x0C,     /* 0x0C: r5 */
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0E, 16, /* 0x0E: r6, 16 characters */
    OK,     DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

static char name[17];

int main(void)
{
    unsigned char r;
    LogText("GUIDE dialog OK");
    r5 = (unsigned int)"Your name:";
    r6 = (unsigned int)name;
    r = DoDlgBox((void *)&ask);
    if (r == OK || r == DBGETSTRING)
        WPutString(name, 270, 240);
    return 0;
}
```

- **Text.** `DBTXTSTR` shows a fixed string. `DBVARSTR` shows the string a
  register points to: `0x0C` is r5, `0x0E` is r6, and so on (the byte is
  the register's zero-page address).
- **Input.** `DBGETSTRING` edits a buffer, and RETURN closes the box with
  the result `DBGETSTRING`.
- **Buttons.** `OK`, `CANCEL`, `YES` and `NO` are buttons at icon
  positions (`DBI_X_0`, `DBI_Y_2` ...).
- **Other commands.** `DBSYSOPV` closes the box on any click. `DBUSRICON`,
  `DB_USR_ROUT` and `DBOPVEC` run your own code.

Text input outside a dialog is `WGetString(buffer, max, x, y, flags,
fault)`; `keyVector` is called when RETURN ends it.

**A box of your own.** A box with a `DB_USR_ROUT` can draw what it likes
and set `keyVector`, `otherPressVec` and `appMain` for itself while it is
open (the box gives the program's back when it closes); its routine ends
the box by setting `sysDBData` and calling `RstrFrmDialogue`. That call
returns from `DoDlgBox` from inside the C routine, which leaves cc65's
C stack pointer where the routine had it: open such a box with
`vr_dlgbox(table)` (`vr.h`), which is `DoDlgBox` that puts the C stack
back. (A C statement after `DoDlgBox` cannot do it: cc65's optimizer
removes stores to its stack pointer.)

**An alert with the program's icon** (`vralert.h`, Veranda Look 3
"Sunroom"): `vr_alert(kind, headline, explanation)` shows the program's
icon at the left, the headline in bold (two lines at most), a plain
explanation under it (two lines, wrapped at spaces) and the buttons at
the bottom right: `VA_OK`, `VA_YESNO` (No, Yes), `VA_YNC` (No at the
left, Cancel, Yes) or `VA_OKCANCEL`. The default button (OK, Yes) has a
double frame; Return chooses it, Esc cancels. It returns `OK`, `YES`,
`NO` or `CANCEL`. The icon is a 32 x 32 one-bit picture made from your
colour icon when you build:

```make
alerticon.c: icon.txt
	python3 $(SDK)/tools/vicon.py --alert icon.txt alerticon.c
```

```c
#include <vralert.h>
extern const unsigned char vr_icon[128];       /* alerticon.c */
...
vr_alert_icon = vr_icon;                        /* once */
if (vr_alert(VA_YNC, "Save the changes to \"Letter\"?",
             "If you don't save, your changes are lost.") == YES)
    save();
```

Write the headline as the question or the fact, and the explanation as
what it means or what to do, rather than one sentence split in two.

## 6. Files

Veranda reads and writes the SD card's FAT32 file system through the
X16's DOS. There are two kinds of file.

**Plain files** are any file on the card, read and written as a stream:

```c
/* example: files */
#include <veranda.h>
#include <vr.h>
#include <string.h>

static const char text[] = "Written by the Veranda guide.";
static char back[40];

int main(void)
{
    unsigned char h;
    unsigned int n;
    static unsigned char entry[3 + 64];
    unsigned char files = 0;

    h = FOpen("GUIDE.TXT", 'w');        /* create or replace */
    if (h < 2)
        return 0;                       /* below 2: an error */
    FWrite(h, (void *)text, sizeof text);
    FClose(h);

    h = FOpen("GUIDE.TXT", 'r');
    n = FRead(h, back, sizeof back);
    FClose(h);

    if (DirOpen("*") == 0)              /* the current directory */
        while (DirNext(entry) == 0)     /* entry: 'D' or 'F', size, name */
            ++files;

    if (n == sizeof text && memcmp(text, back, n) == 0 && files > 0)
        LogText("GUIDE files OK");
    return 0;
}
```

- **Handles.** `FOpen` returns a handle from 2 up; below 2 is an error.
- **Modes.** `'r'` reads; `'w'` creates or replaces; `'m'` reads and
  writes, with `FSeek`.
- **Directories.** `ChDir` and `MkDir` take DOS paths (`"/"`, `".."`,
  `"NOTES"`).
- **Status.** After any call, `dosStatus` holds the DOS's status code.

**GEOS files** have an info block: their type, their icon, the
application that made them. On the card they are stored as `Name.cvt`.
Applications and documents are GEOS files. A **record file**, or VLIR, is
a GEOS file of up to 127 records, each read and written whole. Veranda
holds an open record file in RAM banks and writes it back when it is
closed:

```c
/* example: records */
#include <veranda.h>
#include <vr.h>
#include <string.h>

static char name[] = "Guide data";
static unsigned char hdr[256];
static char rec[32];

int main(void)
{
    memset(hdr, 0, sizeof hdr);
    hdr[0] = (unsigned int)name & 255;  /* the file's name */
    hdr[1] = (unsigned int)name >> 8;
    hdr[2] = 3;                         /* the icon: 3 bytes x 21 rows */
    hdr[3] = 21;
    hdr[4] = 0xBF;
    hdr[68] = 0x83;                     /* a USR file */
    hdr[69] = APPL_DATA;                /* a document */
    hdr[70] = 1;                        /* a record file */
    memcpy(hdr + O_GHFNAME, "Guide data  V1.0", 17);

    if (SaveFile(hdr, 0))               /* create it, empty */
        return 0;
    if (OpenRecordFile(name))
        return 0;
    AppendRecord();                     /* record 0 */
    WriteRecord("first record", 13);
    AppendRecord();                     /* record 1 */
    WriteRecord("second record", 14);
    CloseRecordFile();                  /* written back to the card */

    OpenRecordFile(name);
    PointRecord(1);
    ReadRecord(rec, sizeof rec);
    CloseRecordFile();
    if (strcmp(rec, "second record") == 0)
        LogText("GUIDE records OK");
    return 0;
}
```

The other record calls are `InsertRecord`, `DeleteRecord`,
`NextRecord`, `PreviousRecord` and `usedRecords`. `FindFTypes` lists the
GEOS files of a type, and `GetFile` starts an application or opens a
document with its application.

**Documents.** An application says which plain files it opens in its
`app.hdr`: `documents = X16S CSV` (up to four extensions of 1-4
characters; `vpack.py` puts them in the info block, bytes 144-159). A
double click on such a file in the shell starts the application with
`GetFile(app, ST_LD_DATA, 0, name, 0)`: the application finds
`r0L & ST_LD_DATA` at its start (read it before anything else uses r0:
first thing in `main()`), the file's whole name in `dataLongName` (up to
`LONG_MAX`, 63 characters; API 5) and in `dataFileName` GEOS's 16-character
form of it (the name itself, or for a longer one its short form, such as
`Holiday~1D38.txt`, which every GEOS file call and `FOpen` take for the
long file: DECISIONS V82), and the file's folder in `curDirName`.
The shell looks for the application in the file's folder, then in the top
folder: then the application starts in the top folder, and
`ChDir(curDirName)` takes it to the document.

**Long names** (API 5; DECISIONS V82). GEOS's file calls take names of 16
characters. A native program sets `longNames = LONG_NAMES` (once, at its
start; the kernel clears it when a program starts) and `FindFile`,
`GetFile` (the program and its document), `OpenRecordFile`, `SaveFile`,
`DeleteFile`, and `GetFHdrInfo` and `LdFile` after `FindFile`, take FAT
names of up to 63 characters (a GEOS file's without its `.cvt`), so a
document saved as "Holiday sketch from the lake shore 2026" is
`Holiday sketch from the lake shore 2026.cvt` on the card. `RenameFile`
gives `BFR_OVERFLOW` when the two names do not fit one DOS command (use
`FRename`). Declare `api = 5` in `app.hdr`.

**The working folder.** `curDirName` (bytes 0-61) is the application's
working folder: it starts as the folder the shell was showing (with a
document, the document's), and an application may change it (with
`ChDir`) as the user moves around, as the file chooser does. The shell
does not depend on it: it keeps its own folder in the kernel (`SysPrefs`
`DESK_SET`, before it starts a program) and goes back there when the
application quits, crashes or calls `EnterDeskTop` (DECISIONS V63). An
application never needs to put `curDirName` back.

**The Open and Save dialog** (`vrchoose.h`; DECISIONS V79). `DBGETFILES`
lists GEOS files of a type, by their 16-character GEOS names. For any
file by its long FAT name, `vr_file(VRF_OPEN, title, name)` opens Veranda
Look 2's standard dialog over the current folder (`curDirName`): a title
band (drag it to move the box), the name field, the folder pop-up ("In:":
the path's folders, then Documents, Apps and the card), the folders and
files with kind badges and a scroll bar, New folder, a type filter,
Cancel and the default button. Keys: the arrows, PgUp, PgDn, Home, End,
Return (into a folder, or the default button), Esc; when opening a letter
goes to the next name starting with it and Backspace up a folder.
`VRF_SAVE` makes the field editable (it starts with `name`; a click on a
file copies its name). It returns 1 with the name in `name` (64 bytes),
the folder chosen in `curDirName` and as the current directory; 0 if
cancelled. `vr_file_filter`, if set, says which files to show;
`vr_file_types = "Text:TXT MD INI LOG"` adds the type filter's button;
`vr_file_max` limits the name; `vr_file_x`, `vr_file_y` are its place.
It uses one RAM bank while it is open and is about 8 KB of code: a
program short of main RAM compiles the SDK's `src/vrchoose.c` into a
banked overlay of its own (its BSS stays in main RAM; map the overlay
around the call, as Veranda Edit's `file_dlg` does).

## 7. Memory, banks and timers

An application has `$0801-$87FF`: its code, its data and, in C, a 2 KB
stack at the top. For more, the X16's 8 KB RAM banks appear at
`$A000-$BFFF`. `BankAlloc(n)` gives the application n banks in a row
(the first one's number, or 0 if there are not enough), and `BankCopy`
moves bytes between them and main memory:

```c
/* example: banks */
#include <veranda.h>
#include <vr.h>
#include <string.h>

static char a[64], b[64];

int main(void)
{
    unsigned char bank = BankAlloc(2);  /* 16 KB */
    if (bank == 0)
        return 0;
    strcpy(a, "kept in a RAM bank");
    BankCopy(a, (void *)0xA000, sizeof a, 0, bank);      /* bank 0: main RAM */
    BankCopy((void *)0xA000, b, sizeof b, bank, 0);
    BankFree(bank);
    if (strcmp(a, b) == 0)
        LogText("GUIDE banks OK");
    return 0;
}
```

All of an application's banks are freed when it quits.

A larger program can be split into **overlays**:
- **On disk.** Pack the main part and the overlays into one record file
  with `vpack.py`: the main part is record 0, the overlays records 1 and
  up.
- **At start.** Veranda loads the overlays into RAM banks when the
  application starts.
- **In use.** `LoadOverlay(n, address)` copies overlay n to where it was
  linked.
- **In place (API 2).** With `overlays = banked` (and `api = 2`) in
  `app.hdr`, each overlay is kept at `$A000` of a RAM bank of its own and
  runs there: nothing is copied. Link the program with
  `cfg/app-c-ovl.cfg` (each overlay n from the segments OVERLAYn,
  OVLnRO, OVLnDATA and OVLnBSS, at most 8191 bytes; cl65 writes it to
  `<output>.n`), ask for the bank with `LoadOverlay(n, 0)` (the bank in
  `r1L`) and map it with a store to address `$00`; then call its
  functions as any others. Three rules: the kernel maps its own banks at
  `$A000` during a call, so a pointer handed to the kernel (a string for
  `LogText`, a dialog box) must be below `$A000`; resident code that maps
  another bank (a heap) puts the caller's bank back; an overlay's BSS is
  not cleared. The configuration also puts cc65's zero page at `$50`,
  which leaves `$A9-$D3` to the X16 ROM's maths library (ROM bank 4), so
  a program may call it: map ROM bank 4 at `$01` with the interrupt off
  (that bank has no interrupt vectors), call its jump table at `$FE00`,
  put bank 0 back and allow the interrupt again. Its errors (overflow, division by
  zero) jump through BASIC's error vector at `$0300`, which the program
  points at its own handler first (VeraBASIC Run, DECISIONS V86).

**Processes** are timers that call a routine every so many frames (60
frames a second), from the main loop. A table holds each process's
routine and its interval:

```c
/* example: processes */
#include <veranda.h>
#include <vr.h>

static unsigned char ticks;

static void every_tenth(void)
{
    if (++ticks == 6) {
        BlockProcess(0);                /* stop it */
        LogText("GUIDE processes OK");
    }
}

struct proc { void *f; unsigned int frames; };
static struct proc procs[1] = { { every_tenth, 10 } };

int main(void)
{
    InitProcesses(procs, 1);
    RestartProcess(0);                  /* processes start stopped */
    return 0;
}
```

- **Control.** `BlockProcess` and `UnblockProcess` stop and resume a
  process's calls. `FreezeProcess` and `UnfreezeProcess` stop and resume
  its timer. `EnableProcess` runs it once.
- **`Sleep` from C.** `Sleep` returns to its caller's caller, which C
  cannot express. Use a process or `appMain` instead.

## 8. The interrupt

`vr_set_irq(f)` runs a C function every frame inside the interrupt, for
work that must keep time: music, animation. It interrupts the
application's own C code, so it gets its own small stack, and it must not
call Veranda routines that draw or use files. Share data with the rest of
the program through `static` variables:

```c
/* example: irq */
#include <veranda.h>
#include <vr.h>

static volatile unsigned char frames;

static void each_frame(void)
{
    ++frames;
}

static void check(void)
{
    if (frames >= 30) {
        vr_set_irq(0);                  /* off */
        appMain = 0;
        LogText("GUIDE irq OK");
    }
}

int main(void)
{
    vr_set_irq(each_frame);
    appMain = VR_FN(check);
    return 0;
}
```

**The pointer.** It is in `mouseXPos` and `mouseYPosW` (words). The
interrupt updates them, so a C program that needs both at once should
read them twice and use the pair only if the two readings agree.

**Its shape.** `SetPointer(PTR_IBEAM)` shows the I-beam, `PTR_CROSS` the
crosshair, `PTR_BUSY` an animated busy pointer, `PTR_ARROW` the arrow; it
returns the shape before. A program usually sets the shape from `appMain`
according to where the pointer is (Paint: the crosshair over its drawing
area, the I-beam with the text tool; setting the same shape again costs
nothing). Veranda shows the arrow by itself while a menu or a dialog box
is open, and the busy pointer while the main loop has not run for a third
of a second (a long calculation, a file load), so a program need not do
that itself. Every application starts with the arrow.

**Sound and the screen saver.** `Beep()` plays the system's short chime
and returns at once; use it with an error message. `PlaySound(id)` plays
any of the system sounds (API 4, DECISIONS V69): `SND_ERROR` (Beep's),
`SND_WARNING`, `SND_ALARM`, `SND_STARTUP`, `SND_EXIT`, `SND_APP`,
`SND_OPEN` and `SND_CLOSE` (a window of your own), `SND_MENU`,
`SND_TRASH`. They play from the interrupt on PSG voices 14 and 15, which
Veranda keeps for itself; a new one replaces the one playing, and the
user's settings (sounds off, the volume, the menu ticks) apply. The kernel
already plays them at its own events (start-up, a program's start, a desk
accessory, a dialog box with YES and NO, the alarm, the way to BASIC). After `blankDelay` seconds without input (600 at
start-up, 0: never) the screen goes dark; the key or the click that wakes
it is not passed to the program.

**When a program crashes.** A `BRK` (also what a jump into memory full of
zeros runs into), a call to `Panic`, or a stack nearly full in the
interrupt bring up the panic box: the program's name and the address.
Its OK goes back to the desktop with the kernel restored from a clean
copy and every file closed (DECISIONS V50).

## 9. Printing, colour and desk accessories

- **Printing is a file.** `ExportRect(name, left, top, right, bottom,
  screen)` writes an area of the foreground (screen 0) or the back
  screen (1) to a file as a 1 bpp BMP picture, which any PC opens.
- **Printing to PDF.** For a printer, Veranda writes a PDF file that any
  PC prints, with the pages composed at printer resolution.
  `PrintOpen(name, flags)` starts a document: A4, or US Letter with
  `PRINT_LETTER`; 150 dots an inch, or 300 with `PRINT_300DPI`. It leaves
  the page's size in `r1` (bytes a row), `r2` (rows) and `r3` (dots
  across): a page is a 1 bpp bitmap, bit 7 the left dot, 1 = ink, which
  you send in bands of rows, top first, with `PrintBand(rows, count)`, as
  a GEOS printer driver takes its PrintBuffer calls. The rows may be in main RAM
  or at `$A000` in a RAM bank mapped when you call. A page ends after
  its last row, or at `PrintPage()` (the rest white); `PrintClose()`
  finishes the file. `PrintRect(left, top, right, bottom, flags)` prints
  a screen area as a page of its own, scaled: `PRINT_FIT` to fit the
  page, else at 80 screen pixels an inch, as GEOS printed;
  `PRINT_BACK` from the back screen; `PRINT_COLOR` in the ink's colour
  and the cards' paper colours. Each call returns an error, 0 if none.
  A page takes some seconds: Paint's file/print fits its picture on an A4
  or Letter page.
- **Colour.** The bitmap has one ink colour, but each 8 x 8 card can have
  its own paper colour: `ColorRect(x, width, y, height, colour)` (cards;
  colour a palette entry 1-15, 0 the normal paper; 255 clears and turns
  the colours off); `GetCardColor(x, y)` reads one. Menus and dialog boxes
  show on the normal paper: the cards under one are set aside while it
  is open and come back when it closes (a `ColorRect` meanwhile reaches
  them then); a desk accessory runs with the colours hidden and in the
  normal paper and ink. The ink is one colour for the whole screen,
  menus included: set it with `SetColors(0xFFFF, ink)`. `ExportRect`
  with 128 added to its last argument writes the colours too (a 4 bpp
  BMP, the ink its palette entry 1).
- **A full-colour picture** (`#include <vrpic.h>`, DECISIONS V105): a
  game's table or playfield in VERA's 4 bpp tiles under the bitmap, the
  kernel's tile mode that the shell's desktop picture uses. `vr_pic_on()`
  turns it on: the map cleared (every card the paper), tiles 0-15 the 16
  solid colours (so `ColorRect` still works: colour c is tile c in
  palette row 0), palette row 15 the paper as palette entry 0 is then
  (set your paper first: the cards under menus and dialog boxes show
  it), the back screen cleared, palette rows 2-15 kept for the end. The
  program then writes its tiles (from 16, at `VR_PIC_TILES` + 32 t),
  its map entries (card x, y at `VR_PIC_MAP` + 256 y + 2 x: the tile's
  low byte, then palette row << 4, the flips and the tile's bits 8-9)
  and its palette rows 2-13 straight into VRAM. The SDK's
  `mkwall.py --tiles OUT picture.png [more.png]` converts pictures of
  640 x 480 (several at once share their tiles and rows: a lamp lit and
  off) into records for `vr_vram_load(bank)` (record 1 the palette
  rows), `OUT.map` (a map a picture) and `OUT-0.png` (how it will look).
  Up to 480 tiles; 928 if the program keeps no sprite pictures in sprite
  slots 1-7. The bitmap stays on top: keep it empty where the picture
  should show; menus recover from the back screen, so ink you want back
  under a menu goes to both screens. `vr_pic_back()` in `appMain`
  returns 1 once after the program comes back from being put aside
  (Alt + Tab): write your palette rows again then (the tiles and the map
  come back by themselves). `vr_pic_off()` ends it and puts rows 2-15
  back (a program that quits without it is fine too).

```c
/* example: pic */
#include <veranda.h>
#include <vr.h>
#include <vrpic.h>

#define VADDR_L (*(volatile unsigned char *)0x9F20)
#define VADDR_M (*(volatile unsigned char *)0x9F21)
#define VADDR_H (*(volatile unsigned char *)0x9F22)
#define VDATA0  (*(volatile unsigned char *)0x9F23)
#define VCTRL   (*(volatile unsigned char *)0x9F25)

static void vat(unsigned long a)
{
    VCTRL = 0;
    VADDR_L = (unsigned char)a;
    VADDR_M = (unsigned char)(a >> 8);
    VADDR_H = (unsigned char)((a >> 16) & 1) | 0x10;   /* increment 1 */
}

int main(void)
{
    unsigned char x, y, i;
    vr_pic_on();
    vat(VR_PIC_PALETTE + 4 * 32);           /* palette row 4: a sunset */
    for (i = 0; i < 16; ++i) {
        VDATA0 = (unsigned char)(i << 4 | (15 - i) / 2);
        VDATA0 = 15;
    }
    for (y = 2; y < 60; ++y) {              /* each card a solid tile in row 4 */
        vat(VR_PIC_MAP + 256UL * y);
        for (x = 0; x < 80; ++x) {
            VDATA0 = 1 + (x + y) % 15;      /* tile c: every pixel colour c */
            VDATA0 = 4 << 4;
        }
    }
    LogText("GUIDE pic OK");
    return 0;
}
```

```c
/* example: print */
#include <veranda.h>
#include <vr.h>
#include <string.h>

static unsigned char band[16 * 155];    /* 16 rows of an A4 page at 150 dpi */

int main(void)
{
    unsigned char e, i, y;
    unsigned int rows;
    e = PrintOpen("GUIDE.PDF", 0);      /* A4, 150 dots an inch */
    rows = r2;                          /* 1754 rows of r1 = 155 bytes */
    for (y = 0; !e && y < 8; ++y) {     /* page 1: 128 rows of stripes */
        for (i = 0; i < 16; ++i)
            memset(band + i * 155, (y + i) & 4 ? 0xF0 : 0x0F, 155);
        e = PrintBand(band, 16);
    }
    if (!e)
        e = PrintPage();                /* the rest of page 1 white */
    WFrameRectangle(0xFF, 100, 100, 300, 200);
    WPutString("A page of its own", 140, 154);
    if (!e)
        e = PrintRect(100, 100, 300, 200, PRINT_FIT);   /* page 2 */
    if (!e)
        e = PrintClose();
    if (!e && rows == 1754)
        LogText("GUIDE print OK");
    return 0;
}
```

A **desk accessory** is a small program that runs over an application:
a calculator, a note pad. Build it like an application, with `type =
deskacc` and `mode = keep` in `app.hdr`. An application opens one with
`GetFile`, by name; Veranda puts the application aside whole (its RAM,
zero page, stack, variables, menus, processes and both screens),
starts the accessory over the screen as it is, and when the accessory
calls `RstrAppl` the application comes back exactly as it was, returning
from `GetFile`. To let the user choose, list the accessories with a
dialog box's `DBGETFILES` and `r7L = DESK_ACC`. An accessory should not
open a record file while the application has one open (`RecordInfo`
returns 0 when one is). Veranda's own accessories (`apps/dex`,
`apps/calendar`, `apps/prefs`) share a small toolkit, `apps/daui`: a
window with a title bar and a close box, buttons, text fields, boxes,
and the system's data files (in `/VERANDA/.SYSTEM`); `SysPrefs` reads
and sets the system's settings and its alarm table (DECISIONS V56).
Accessories, like applications, live in `/VERANDA/APPS`: list them from
there (`vr_cd(VR_APPS)` before the `DBGETFILES` box, `vr_cdback()`
after `GetFile` returns).

**The card's folders** (`#include <vrpath.h>`, DECISIONS V71):
`/VERANDA` the system, `/VERANDA/APPS` the applications and accessories,
`/VERANDA/FONTS` the fonts, `/VERANDA/.SYSTEM` the system's data
(hidden), `/DOCUMENTS` the user's files. `vr_cd(VR_SYS / VR_DATA /
VR_APPS / VR_DOCS)` makes one of them the current directory (with the
fallbacks: no `/VERANDA`, the root; no `APPS`, `/VERANDA`; `.SYSTEM`
and `/DOCUMENTS` made when missing) and returns its path;
`vr_home(r0L)` at a program's start makes `curDirName`, the working
folder, `/DOCUMENTS` when the shell started it without a document from
the system's folders (the shell does so itself too), and current, so its
first Open and Save go there. The paths are veranda.h's `VR_SYSDIR`,
`VR_APPSDIR`, `VR_DATADIR`, `VR_DOCSDIR`, and `VR_DATAPATH`
(`"//VERANDA/.SYSTEM/:"`, for `FOpen` by a path).

```c
/* example: deskacc */
#include <veranda.h>
#include <vr.h>

/* the whole accessory: a box, closed by a click (or a key) */
static void done(void)
{
    RstrAppl();                 /* back to the application */
}

int main(void)
{
    SetPattern(0);
    WRectangle(240, 200, 399, 279);
    WFrameRectangle(0xFF, 240, 200, 399, 279);
    WPutString("Click to close.", 270, 244);
    otherPressVec = VR_FN(done);
    keyVector = VR_FN(done);
    LogText("GUIDE deskacc OK");
    return 0;
}
```

## 10. The clipboard

Veranda's clipboard is GEOS's: the **Text Scrap** and the **Photo Scrap**,
two GEOS files in the system's data folder (`/VERANDA/.SYSTEM`, or the
root when there is no `/VERANDA`), so a text copied in one program pastes
in another. `#include <scrap.h>`; the functions are in `veranda.lib`
and find the folder themselves (your program's directory stays as it
is). Each returns 0 or an error, those that return a length 0 for none.

- **Text.** `scrap_put_text(text, n)` writes plain text (a `'\n'` or CR
  ends a paragraph); `scrap_get_text(buffer, size)` reads it back as
  plain text, the paragraphs ended by CR (13), GEOS's style and ruler
  codes left out. `scrap_put_text_raw` and `scrap_get_text_raw` take
  GEOS text with its codes as it is (a NEWCARDSET first: the font and
  style). Long text goes in parts: `scrap_text_begin(n)`, then
  `scrap_write` of n bytes in all, then `scrap_close`.
- **Pictures.** `scrap_put_photo(width, height, get, colour)` writes a
  picture of width cards (8 pixels) by height rows: `get(y, row)` gives
  row y, `colour(cx, cy)` each card's colour (the ink in the high
  nibble, the paper in the low one), or pass 0 for black and white.
  `scrap_photo_size(&w, &h)` tells a Photo Scrap's size, and
  `scrap_get_photo(put, colour)` hands its rows to `put(y, row)`, and its
  cards' colours, if it has any, to `colour(cx, cy, c)`.
- **Changes.** `scrap_stamp(kind, stamp)` gives 8 bytes that change
  whenever the scrap (`SCRAP_TEXT` or `SCRAP_PHOTO`) is written again:
  keep the stamp of your own last copy, and you know when another
  program has put something there since.
- **Short of room?** The SDK's `src/` has the library's C sources: a
  program with overlays can compile them into one of its own (Veranda
  Calc does).
- **A text editor of your own?** `src/textkit/` is Veranda Edit's text
  engine as sources (DECISIONS V93): the gap buffer across RAM banks
  (`buf.s`), editing and the line count, undo, the `PutCards` view, find
  and replace, the Text Scrap, plain files with their line ends.
  `textkit.h` lists what your program gives it (a `tkapp.h` of your own:
  the dialog boxes, the status bar, its configuration); Veranda Edit and
  VeraBASIC both compile it.

```c
/* example: clip */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <scrap.h>

static char back[64];
static unsigned char st1[8], st2[8];

int main(void)
{
    scrap_put_text("Hello,\nclipboard", 16);
    scrap_stamp(SCRAP_TEXT, st1);
    scrap_get_text(back, sizeof back);   /* "Hello," CR "clipboard" */
    scrap_put_text("again", 5);
    scrap_stamp(SCRAP_TEXT, st2);
    if (!strcmp(back, "Hello,\rclipboard") && memcmp(st1, st2, 8))
        LogText("GUIDE clip OK");
    return 0;
}
```

## 11. Fonts

Text draws in GEOS fonts. Besides the system font, Veranda keeps fonts in
RAM banks of its own, loaded once and shared by every program (API 3):

- **Loading.** `LoadFont(name, size)` finds the GEOS font file `name`
  (its FAT name without `.cvt`; long names are fine) in the fonts folder
  `/VERANDA/FONTS`, else in the current directory, reads the record of
  that point size into RAM banks and returns a handle, or `FONT_NONE`.
  Asking again for a font that is loaded already costs nothing: the
  handle comes back at once. Two fonts are built in: `"System"` (9
  points, handle 0) and `"Veranda UI"` (12 points, `FONT_UI`).
- **Using.** `UseFont(handle)` makes it the current font, as
  `LoadCharSet` does for a font in your own memory; `UseFont(0)` is the
  system font. Measure text with `GetCharWidth` (the font variables
  `curIndexTable` and `cardDataPntr` do not point into your memory for a
  banked font). Fonts stay loaded after your program ends, until another
  program needs the RAM; a handle stays valid while your program runs.
- **Finding out.** `FontList(buffer, max)` names the installed fonts
  (`FONT_NAME_LEN` bytes each: "System", "Veranda UI", then the fonts
  folder's), `FontSizes(name, buffer)` the point sizes of one, and
  `FontInfo(handle, name)` a loaded font's size, with its height in `r1L`
  and its baseline in `r1H`.
- **Choosing.** `#include <fontpick.h>`: `FontPick(&fp)` opens the
  standard font dialog box (the fonts, their sizes, a preview) and on OK
  gives the name, the size and the loaded font's handle in `fp`.
- **A modern look.** `theme_load(); theme_menus();` (`theme.h`) before
  `DoMenu`: the menu bar in Veranda Look 2, its menus and your dialog
  boxes in the Veranda UI font (`uiFont = FONT_UI`; measure your lists'
  widths in it). Name your first menu after your program. `vrwin.h`
  gives your window the title band, a toolbar and a status bar
  (`vr_win`). Both are reset whenever a program starts; GEOS ports leave
  them alone and keep GEOS's look. `vr_tile(x, y, glyph, buf)` (`vr.h`)
  draws an application's tile as the shell shows it: a 32 x 32 glyph in
  the rounded frame at card x, line y (colour its 4 x 4 cards with
  `ColorRect`; `buf`, 128 bytes below `$A000`, is where it is composed).

```c
/* example: fonts */
#include <veranda.h>
#include <vr.h>

static char names[4 * FONT_NAME_LEN];

int main(void)
{
    unsigned char h = LoadFont("Veranda UI", 12), n;
    UseFont(h);
    WPutString("Veranda UI, 12 points", 20, 40);
    n = FontList(names, 4);
    if (h == FONT_UI && n >= 2 && FontInfo(h, 0) == 12 && r1L == 12)
        LogText("GUIDE fonts OK");
    UseFont(0);
    return 0;
}
```

## 12. Building, packing and running

- **The header.** `app.hdr` names the application: name, class (`"Name
  V1.0"`, used to find a document's application), author, description,
  video mode and API level. Add a 24x21 `icon.pbm`, and
  `make` builds `Name.cvt`.
- **Running.** Copy the CVT to the SD card, next to the shell, and
  double-click it there. Or run `make run` (the emulator, with the
  current folder as the card), or `vrun Name.cvt`.
- **Testing.** `make test` runs it headless and passes when it logs its
  line.
- **Checking.** Check the API level you ask for (`api` in `app.hdr`):
  Veranda refuses an application that needs a newer one, with
  `TOO_NEW`.

For the details of every call (its registers, flags and errors), see
`API.md`. For the network (TCP connections through the Wi-Fi modem of
TexElec's Serial & ESP32 Network Card: `vrnet.h`), see `NET.md`.
