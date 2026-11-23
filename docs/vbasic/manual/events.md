# 4. Events and the program model

A console program runs from its first line to its last. A Veranda
program does more: it draws its windows and menus, then waits, and the
user decides what happens next by choosing a menu item, clicking,
typing, turning the wheel, closing a window or just letting a timer
tick. This chapter is how VeraBASIC runs such a program; the statements
themselves are in [Veranda extensions, part 1](extensions.md#2-events).

## The two halves of a program

```basic
' the main lines set things up; the handlers do the work
OPTION INTEGER
count = 0
WINDOW #1, 20, 10, 40, 12, "Counter", CLOSE, STATUS 2
ON CLOSE #1 CALL Done
TIMER 1, 2 CALL Tick
PRINT "the main lines are done"

SUB Tick
  count = count + 1
  WINDOW STATUS #1, STR$(count), ""
  IF count = 5 THEN Done
END SUB

SUB Done
  PRINT "counted"; count
  END
END SUB
```

- **The main lines** run first, top to bottom: open the windows, build
  the menus, bind the handlers (`{ON}` ... `{CALL}`, `{ITEM}`, `{TIMER}`),
  set the variables.
- When they end (or reach `WAIT EVENTS`), a program that has bound a
  handler does not end: it waits for events. A program with no handler
  ends there, as a console program does.
- **The handlers** are SUBs without arguments. Each event calls the one
  bound to it. Globals keep their values between handlers; a handler's
  `{LOCAL}` variables last for that call only.
- **`{END}`**, in the main lines or any handler, ends the program. In an
  application made from it (chapter 7), and in VeraBASIC Run, a program
  with windows that ends quits to the shell; from the editor, the editor
  comes back.

## The queue

The kernel never runs BASIC. Its callbacks (a menu item's routine, the
key and press vectors, a process for each `{TIMER}`) only put an event in
a queue of 16 and return; the interpreter takes them out one at a time
between statements:

1. A handler **runs to its end** before the next starts. Events that come
   meanwhile wait in the queue, in their order.
2. A timer has at most **one** event waiting: a handler slower than its
   timer is not flooded, it is called again as soon as it is done.
3. A full queue drops the newest event (a key typed into a busy program
   is lost, as on any machine that is busy).
4. While a menu is open, or a dialog box is up, BASIC waits: the kernel
   has the screen.

The interpreter runs in **slices** of about 8 ms from the kernel's main
loop, so the pointer, the menus, the clock and the switcher stay alive
while BASIC computes. A long loop in a handler does not stop that, but it
does keep the other handlers waiting; `{DOEVENTS}` inside it runs the
ones queued so far, and `{SLEEP}` takes events while it waits.

```basic
' a long job that keeps its window's status bar going
OPTION INTEGER
WINDOW #1, 20, 10, 40, 12, "Working", STATUS 2
TIMER 1, 1 CALL ShowTicks
FOR i = 1 TO 2000
  IF i MOD 250 = 0 THEN DOEVENTS
NEXT
PRINT "done after"; ticks; "ticks shown"
END

SUB ShowTicks
  ticks = ticks + 1
  WINDOW STATUS #1, "working" + STR$(ticks), ""
END SUB
```

## What an event knows

| Event | Bound by | In the handler |
|---|---|---|
| a menu item | `{ITEM}` `text$, sub` | `{CHECK}` to tick it; the item's text is not passed |
| a click | `{ON}` `{CLICK}` `{CALL}` | `{MOUSEX}`, `{MOUSEY}` (in the window `{WINDOW}` `{USE}` chose), `{MOUSEB}` (bit 7: the release), `{HIT}` for the part of a window |
| a key | `{ON}` `{KEY}` `{CALL}` | `{KEY$}`, `{KEYCODE}`, `{KEYMODS}` |
| the wheel | `{ON}` `{WHEEL}` `{CALL}` | `{WHEEL}`: the turn, -8 to 7 |
| a close glyph | `{ON}` `{CLOSE}` `#w` `{CALL}` | the window is still open: the handler closes it, or ends |
| Quit | `{ON}` `{QUIT}` `{CALL}` | VeraBASIC Run's own Quit (or an application's): the handler decides; without one, the program ends |
| a timer | `{TIMER}` `n, frames` `{CALL}` | `{TI}`, `{TIME$}` |

## Errors in handlers

An error in a handler ends the program as an error anywhere does: the
editor shows the line (chapter 6), VeraBASIC Run and an application show
a box with the error and its line, then quit. `{TRY}` ... `{CATCH}` inside
the handler keeps it going:

```basic
OPTION INTEGER
SUB Safe
  TRY
    x = 10 / zero
  CATCH
    PRINT "caught error"; ERR; "in the handler"
  END TRY
END SUB
zero = 0
Safe
PRINT "still running"
```

## Put aside and back

Alt+Tab (or `{ASIDE}` from the program) puts the whole program aside at
any slice, with its windows, its variables and its timers; the dock shows
it, and a click there brings it back where it was: a loop goes on, a
timer ticks again. A program with `{APP}` `{STAY}` is never put aside: the
switcher offers to quit it. `{TASKS}` says how many programs are aside.

## A program's end

At its end (`{END}`, an error, Stop, or Quit) the runtime takes away
what the program set up: its timers' processes, its menus, the key and
press vectors, its sprites, its open files and its RAM banks. The next
program, or the editor, starts clean.
