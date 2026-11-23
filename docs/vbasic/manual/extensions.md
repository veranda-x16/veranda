# 3. Veranda extensions, part 1

This chapter covers the statements and functions that make a VeraBASIC
program a Veranda program: events, windows, menus, graphics, text and
fonts, colour, the mouse and the keys, timers and sound (VeraBASIC Run
since DECISIONS V89). [Part 2](extensions2.md) has dialogs, files and
folders, the clipboard, icons, tiles, pictures and sprites (V90).

Each statement has its syntax, a listing you can run, and the kernel call
it maps to (docs/API.md). Every listing here is run by gate `vb_ui` on the
X16 and in the reference interpreter, and they must agree.

## 1. The program model

A Veranda program draws its own windows and menus, then waits for
events: a menu item chosen, a click, a key, the wheel, a window's close
glyph, a timer. Each event calls the SUB it is bound to.

- Kernel callbacks only **queue** an event (16 at most) and return. BASIC
  never runs inside the kernel.
- The interpreter runs in slices of about 8 ms from the main loop, so the
  menus, the clock, the pointer and the switcher keep working while BASIC
  runs. While a menu is open, BASIC waits.
- Handlers **run to completion**, one at a time. Events that come
  meanwhile wait.
- The main lines run first. When they end (or at `WAIT EVENTS`), a program
  with handlers waits for events. `END` in any handler ends the program.
- Inside a long loop, `DOEVENTS` runs the handlers of the events queued so
  far. `SLEEP` takes events while it waits.
- Alt+Tab (or `ASIDE`) puts a running program aside at any slice; it goes
  on where it was when it comes back.
- Once a program opens a window or uses `SCREEN FULL`, its console is
  hidden: `PRINT` still goes to it, but the screen is the program's.

**Coordinates** are pixels of the 640 x 480 screen. After `WINDOW USE #w`
they are relative to window w's body and drawing is clipped to it; the
mouse's `MOUSEX` and `MOUSEY` are in the same coordinates. Statements that
work in cards (`CARDS`, `PAPER`, `CARDCOLOR`, `COPY`, `SCROLL`: 8 x 8
pixels, 80 x 60) count from the body's first card.

**Colour honesty:** VERA at 1 bit a pixel has one ink for the whole
screen and one paper colour for each 8 x 8 card. Colour in VeraBASIC
means `PAPER` areas.

## 2. Events

| Statement | Binds | Kernel side |
|---|---|---|
| `ON CLICK CALL sub` | a press of the left button outside the menus, and its release | `otherPressVec` |
| `ON KEY CALL sub` | a key | `keyVector` |
| `ON WHEEL CALL sub` | a turn of the wheel | `GetMouse`, polled by a process |
| `ON CLOSE #w CALL sub` | window w's close glyph | `vr_win_hit` (`VW_XCLOSE`) on a press |
| `ON QUIT CALL sub` | Quit from VeraBASIC Run's own menu while the program runs | the runtime's menu |
| `ITEM text$, sub` | a menu item | the item's routine (`DoMenu`) |
| `TIMER n, frames CALL sub` | timer n (1-8) | `InitProcesses`, `RestartProcess` |
| `WAIT EVENTS` | the main lines end here | `appMain` |
| `DOEVENTS` | the handlers of the queued events | `appMain` |

A handler is a `SUB` with no arguments. In it, `MOUSEX`, `MOUSEY` and
`MOUSEB` are where the click was, `KEY$`, `KEYCODE` and `KEYMODS` the key,
`WHEEL` the wheel's movement.

### ON ... CALL

```basic
' ON CLICK, ON KEY, ON WHEEL: bound, then a timer ends the program
OPTION INTEGER
WINDOW #1, 20, 10, 40, 12, "Events", STATUS 2
ON CLICK CALL Clicked
ON KEY CALL Typed
ON WHEEL CALL Turned
ON CLOSE #1 CALL Clicked
TIMER 1, 5 CALL Done
SUB Clicked : PRINT "click at"; MOUSEX; MOUSEY : END SUB
SUB Typed : PRINT "key "; KEY$ : END SUB
SUB Turned : PRINT "wheel"; WHEEL : END SUB
SUB Done : PRINT "no events came" : END : END SUB
```

### TIMER

`TIMER n, frames CALL sub` calls the SUB every so many frames (60 a
second). `TIMER n OFF` pauses it (`FreezeProcess`), `TIMER n ON` lets it go
on (`UnfreezeProcess`), `TIMER n STOP` ends it. A timer has one event
queued at a time, so a slow handler is not flooded.

```basic
' two timers; one paused, then both stopped
OPTION INTEGER
WINDOW #1, 20, 10, 40, 12, "Timers", STATUS 2
TIMER 1, 2 CALL Fast
TIMER 2, 10 CALL Slow
TIMER 1 OFF
TIMER 1 ON
SUB Fast : f = f + 1 : END SUB
SUB Slow
  s = s + 1
  WINDOW STATUS #1, "slow" + STR$(s), ""
  IF s = 3 THEN TIMER 1 STOP : TIMER 2 STOP : PRINT "stopped" : END
END SUB
```

### WAIT EVENTS, DOEVENTS, SLEEP

```basic
' a long loop that lets its timer run; SLEEP takes events too
OPTION INTEGER
TIMER 1, 1 CALL Tick
FOR i = 1 TO 500
  IF i MOD 100 = 0 THEN DOEVENTS
NEXT
SLEEP 10
PRINT "the loop is done"
done = 1
WAIT EVENTS
SUB Tick : IF done THEN END
END SUB
```

`WAIT EVENTS` inside a handler is an error (*Illegal quantity*).

## 3. Windows

| Statement / function | Maps to |
|---|---|
| `WINDOW #w, x, y, wc, hc, title$ [, TOOL n] [, STATUS n] [, CLOSE] [, FRAME] [, SHADOW]` | `struct vrwin`, `vr_win` |
| `WINDOW TITLE #w, title$` | `vr_win_title` |
| `WINDOW STATUS #w, left$, right$` | `vr_win_status` |
| `WINDOW USE #w` (`#0`: the screen) | the origin; `clipOn`, `leftMargin`, `rightMargin`, `windowTopW`, `windowBottomW` around each drawing |
| `WINDOW BACK #w`, `WINDOW FRONT #w` | `VW_BACK`, `vr_win_title` |
| `WINDOW CLOSE #w` | `WRectangle` and `ColorRect` in the desk's colour |
| `HIT(#w, x, y)` | `vr_win_hit`: 0 outside, 1 title, 2 close glyph, 3 tool band, 4 body, 5 status band |
| `BODYTOP(#w)`, `BODYBOTTOM(#w)` | `vr_win_top`, `vr_win_bottom` |
| `SCREEN FULL [title$]` | the menu bar as a title band (`vr_bar_title`'s layout) |

Windows are 1 to 4, in cards: x and y their top left card, wc and hc their
size (at least 6 x 4, under the menu bar, on the screen). The first
`WINDOW` hides the console and clears the screen to the desk's colour.

```basic
' two windows, one in use, a hit test
OPTION INTEGER
WINDOW #1, 4, 4, 40, 20, "One", FRAME, STATUS 2
WINDOW #2, 30, 14, 40, 20, "Two", CLOSE, FRAME, SHADOW
WINDOW BACK #1
WINDOW STATUS #1, "left", "right"
WINDOW USE #2
TEXT 8, 20, "Drawn in window two"
PRINT BODYTOP(#2); BODYBOTTOM(#2); HIT(#2, 10, 10); HIT(#2, 300, -8)
WINDOW TITLE #2, "Two, renamed"
WINDOW FRONT #1
WINDOW CLOSE #2
END
```

```basic
' SCREEN FULL: a full-screen program, its title in the menu bar
OPTION INTEGER
MENU "Full" : ITEM "Quit", DoQuit
MENU SHOW
SCREEN FULL "A full screen"
BOX 100, 100, 200, 150
END
SUB DoQuit : END : END SUB
```

## 4. Menus

| Statement | Maps to |
|---|---|
| `MENU title$` | a menu of the bar; its `ITEM`s follow |
| `ITEM text$ [, sub [, key$]]` | an item; Ctrl and the key is its shortcut |
| `END MENU` | (optional) the end of a menu's items |
| `MENU SHOW` | the tables in main RAM, `theme_menus`, `DoMenu` |
| `MENU ENABLE menu$, item$, on` | an item disabled (shown in parentheses) or enabled again |
| `CHECK item$, on` | a check mark ("* ") before an item |

The first menu is named after the program (Look 2): its `APP NAME`, else
its file's name; `APP CLASSIC` keeps the program's own title. An
`ITEM "-"` is not an item: the item after it starts a group, under a
dotted line (none before a menu's first item). Up to 8 menus and 40
items. A `MENU` after `MENU SHOW` starts a new bar. Shortcuts are Ctrl
and the letter, shown at the menu's right (*Ctrl B*); Ctrl+C stops the
program unless an item has C.

```basic
' a menu bar of two menus, one item checked, one disabled
OPTION INTEGER
APP NAME "Menus"
MENU "Menus" : ITEM "About Menus", About
MENU "Edit"
  ITEM "Cut", DoCut, "X"
  ITEM "-"
  ITEM "Bold", DoBold, "B"
END MENU
MENU SHOW
CHECK "Bold", 1
MENU ENABLE "Edit", "Cut", 0
END
SUB About : END SUB
SUB DoCut : END SUB
SUB DoBold : END SUB
```

## 5. Graphics

| Statement / function | Maps to |
|---|---|
| `CLS` | `WRectangle` in pattern 0: the body in use, or the screen under the menu bar |
| `PATTERN n` | `SetPattern` (0-33; 0 paper, 1 ink: the default) |
| `BOX x1, y1, x2, y2` | `WRectangle` in the pattern |
| `FRAME x1, y1, x2, y2` | `WFrameRectangle` |
| `INVERT x1, y1, x2, y2` | `WInvertRectangle` |
| `LINE x1, y1, x2, y2 [, INK or ERASE]` | `WDrawLine` |
| `PLOT x, y [, INK or ERASE]` | `WDrawPoint` |
| `POINT(x, y)` | `WTestPoint`: 1 ink, 0 paper |
| `COPY x, y, w, h TO x2, y2` | `CopyRect` (x, w, x2 in cards) |
| `SCROLL x, w, top, bottom, dy` | `ScrollRect` (x, w in cards) |
| `POINTER ARROW / BUSY / IBEAM / CROSS` | `SetPointer` |

```basic
' patterns, boxes, lines and points
OPTION INTEGER
WINDOW #1, 2, 3, 76, 40, "Graphics", FRAME
WINDOW USE #1
FOR p = 0 TO 7
  PATTERN p
  BOX p * 40 + 8, 8, p * 40 + 40, 40
  FRAME p * 40 + 8, 8, p * 40 + 40, 40
NEXT
PATTERN 1
FOR a = 0 TO 200 STEP 25 : LINE 10, 250, 10 + a, 60 : NEXT
PLOT 300, 100 : PLOT 302, 100, ERASE
INVERT 400, 60, 480, 120
PRINT POINT(300, 100); POINT(420, 80)
CLS
END
```

```basic
' COPY and SCROLL; POINTER
OPTION INTEGER
WINDOW #1, 2, 3, 76, 40, "Copy", FRAME
WINDOW USE #1
CARDS 1, 1, "copied"
COPY 1, 8, 10, 8 TO 20, 8
SCROLL 1, 30, 8, 63, -8
POINTER BUSY
POINTER ARROW
END
```

## 6. Text and fonts

| Statement / function | Maps to |
|---|---|
| `TEXT x, y, s$` | `WPutString` (y the baseline) in the font and style |
| `FONT name$, size` | `LoadFont`, `UseFont` (the fonts folder; error 24 *Font not found*) |
| `FONT UI`, `FONT SYSTEM` | `UseFont(FONT_UI)`, the system font |
| `STYLE n` | `currentMode`: `BOLD`, `ITALIC`, `UNDERLINE`, `OUTLINE`, `REVERSE` added |
| `TEXTWIDTH(s$)` | `GetCharWidth` (and a pixel a character in bold) |
| `FONTHEIGHT` | `FontInfo` |
| `CARDS column, row, s$ [, REVERSE or BOLD]` | `PutCards`, the ROM's 8 x 8 font |

```basic
' fonts and styles, a centred line, cards
OPTION INTEGER
WINDOW #1, 4, 4, 60, 30, "Text", FRAME
WINDOW USE #1
FONT UI
TEXT 10, 20, "The UI font"
STYLE BOLD + UNDERLINE
TEXT 10, 40, "Bold, underlined"
STYLE 0
FONT "System", 9
TEXT 10, 60, "The system font"
w = TEXTWIDTH("Centred")
TEXT (480 - w) \ 2, 90, "Centred"
PRINT w; FONTHEIGHT
CARDS 1, 14, "cards", REVERSE
END
```

## 7. Colour

| Statement / function | Maps to |
|---|---|
| `PAPER column, row, w, h, colour` | `ColorRect` |
| `CARDCOLOR(column, row)` | `GetCardColor` |
| `INK $RGB` | `SetColors` (the screen's one ink) |
| `PALETTE n, $RGB` | palette entries 12-15 only (2-11 are Look 2's) |

The colours are Look 2's palette entries: `PAPER` (0), `INK` (1), `CHROME`,
`SIDEBAR`, `TITLE` (5), `YELLOW`, `RED`, `GREEN`, `PURPLE`, `ORANGE`,
`CYAN`, `SKY`, `SKY2`, `HILL`, `DUSK`. In dark mode they are the dark
look's, for free.

```basic
' papers, a palette entry of the program's own
OPTION INTEGER
WINDOW #1, 4, 4, 60, 30, "Colour", FRAME
WINDOW USE #1
PAPER 1, 1, 20, 3, YELLOW
PAPER 1, 5, 20, 3, SKY
PALETTE 13, $F80
PAPER 22, 1, 20, 7, SKY2
PRINT CARDCOLOR(1, 1); CARDCOLOR(22, 5)
INK $223
END
```

## 8. The mouse and the keys

| Function / statement | Maps to |
|---|---|
| `MOUSEX`, `MOUSEY` | `mouseXPos`, `mouseYPosW` (in a click handler: the click's) |
| `MOUSEB` | `mouseButtons`: bit 0 left, 1 right, 2 middle; in a click handler bit 7 a release |
| `WHEEL` | `GetMouse`'s x (signed; in a wheel handler: its movement) |
| `MOUSEIN(x1, y1, x2, y2)` | `WIsMseInRegion` |
| `MOUSE LIMIT x1, y1, x2, y2` | `WSetMouseRegion` |
| `INKEY$` | the next key typed, "" when none |
| `KEY$`, `KEYCODE`, `KEYMODS` | in a key handler: `keyData`, `keyDataMods` (Shift 1, Ctrl 2, Alt 4, GUI 8) |

```basic
' where the pointer is, the pointer kept in a box
OPTION INTEGER
PRINT MOUSEX >= 0; MOUSEY >= 0; MOUSEB; MOUSEIN(0, 0, 639, 479)
MOUSE LIMIT 0, 0, 639, 479
PRINT KEYCODE; KEYMODS; LEN(KEY$); WHEEL
END
```

## 9. Time and the switcher

| Function / statement | Maps to |
|---|---|
| `TIME$` | `hour`, `minutes`, `seconds`: "HH:MM:SS" |
| `DATE$` | `year`, `month`, `day`: "YYYY-MM-DD" |
| `TI` | jiffies since the program started (the core) |
| `SLEEP frames` | waits, taking events |
| `ASIDE` | `TaskCtl(TASK_ASIDE)`: the program is put aside |
| `TASKS`, `TASK$(i)` | `TaskCtl(TASK_INFO)`: how many programs are aside, their names |

```basic
' the clock's texts
PRINT LEN(TIME$); LEN(DATE$); LEFT$(DATE$, 2)
PRINT TASKS >= 0
END
```

## 10. Sound

| Statement | Maps to |
|---|---|
| `SOUND id` | `PlaySound` (`SND_ERROR` ... `SND_TRASH`; silent when the settings say so) |
| `SOUND OFF` | the program's voices silent, its tunes stopped |
| `BEEP` | `Beep` |
| `VOICE v, hz, volume [, wave [, width]]` | VERA's PSG, voices 0-13 (14 and 15 are the system's) |
| `PLAY v, music$` | a sequencer in the interrupt (`intTopVector`): `T` tempo, `O` octave, `L` length, `<` `>`, notes `C`-`B` with `#` `+` `-` and a length, `R` a rest |

At most four tunes play at once.

```basic
' a system sound, a voice, a tune
OPTION INTEGER
SOUND SND_OPEN
BEEP
VOICE 0, 440, 40, PULSE
SLEEP 10
VOICE 0, 0, 0
PLAY 1, "T200 O4 L16 C E G > C"
SLEEP 30
SOUND OFF
END
```

## 11. Errors

| Number | Message |
|---|---|
| 20 | Not available yet (the editor's, the debugger's: phases 5, 6) |
| 24 | Font not found |
| 25 | No such window (`WINDOW USE`, `STATUS`, `BACK`, `FRONT`, `CLOSE` on a window not open) |
| 26 | Too many menus or items (8 menus, 40 items) |

A wrong argument (a window number outside 1-4, a pattern above 33, a
palette entry outside 12-15, a voice above 13) is error 5, *Illegal
quantity*.
