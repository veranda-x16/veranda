# 6. Debugging

VeraBASIC's debugger is part of the editor: a program run from it can be
stopped at a line, looked at, changed, and sent on, and its screen comes
back as it was. *VeraBASIC Run* has none of it; a finished program's
`{TRON}` writes to the emulator's log there.

## Breakpoints

**F9** (*Run > Breakpoint*) puts a breakpoint on the cursor's line, or
takes it off. The line-number gutter comes on, and the line's card in it
turns red with a `*`. Up to 32 lines can have one. When a run reaches a
line with a breakpoint, the program stops **before** the line: the editor
comes back with the line on the selection's blue paper and the pane at
the right (below). A breakpoint stops a program each time its line is
entered: on a loop's body, at each pass; on a `{FOR}`, `{WHILE}` or `{DO}`
line itself, once, when the loop starts. The breakpoints stay with their
lines while you type above them.

A `{STOP}` statement in the program stops it too, after `{STOP}`, as a
breakpoint would. (In *VeraBASIC Run* `{STOP}` ends the program: error 1,
*Stopped*.)

```basic
' a breakpoint on the line of n = n + i stops it ten times; STOP once
OPTION INTEGER
n = 0
FOR i = 1 TO 10
  n = n + i
NEXT
STOP
PRINT "n is"; n
```

## The pane

While a program is stopped, the text narrows and the pane takes the
window's right 33 columns:

| Part | What it shows |
|---|---|
| the head | *Stopped in line 15*, why (a breakpoint, a step, `{STOP}`), and the procedure: *SUB Twice*, *FUNCTION Fact* or *main* |
| *Call stack* | the procedures that are running, the innermost first, each with the line it is at: the line stopped at, then each caller's line (the line of its call); a `{GOSUB}` too (*GOSUB, main*); six of them, then `...` |
| *Watches* | four expressions and their values (below) |
| *Variables* | the procedure's own variables first (its parameters, its `{LOCAL}`s, a `{FUNCTION}`'s result under its name) on white, then the program's globals on the pane's colour; each with its name, its type (*int*, *num* for a float, *str*) and its value; an array as `int()` and its upper bounds (`2, 3`) |

The values are the program's own, read while it is stopped: a string in
quotes (the first 20 characters), a float as `{PRINT}` writes it.

**Tab** gives the pane the keys: **Up** and **Down** choose a watch or a
variable, **PgUp** and **PgDn** page through the variables, and **Return**
does what the row allows:

- on a **variable**, a box asks for its new value: an expression, as in
  the program (`99`, `n * 2`, `"Swift"`); the program goes on with it;
- on an **array**, the pane shows its elements, the last index fastest
  (`grid(1, 2)` is element 6 of a `grid(2, 3)`); Up, Down, PgUp and PgDn
  move along them, **Esc** goes back to the variables;
- on a **watch**, a box asks for its expression.

**Esc** or **Tab** gives the keys back to the text. A click on a row
chooses it, a second click is Return.

## Watches

**Ctrl+W** (*Run > Add a watch...*) asks for an expression to watch: up
to four, kept for the next runs too. Each is evaluated at every break, by
the program's own evaluator, so it may use the program's variables (the
procedure's own first), array elements, the operators and the built-in
functions: `total * 2`, `squares(3) + 1`, `LEFT$(name$, 4) + "!"`,
`n MOD 3 = 0`. A watch may not call the program's `{SUB}`s and
`{FUNCTION}`s (they would run the program), and a name the program has
not got shows *No such variable*. Delete (in the pane) takes a watch off.

## Stepping

| Key | | The program goes on until |
|---|---|---|
| F6 | Continue | a breakpoint or `{STOP}`, or its end |
| F7 | Step | the next line it enters, in any procedure |
| F10 | Step over | the next line entered in this procedure or one that called it: the procedures it calls run through (their breakpoints still stop them) |
| F11 | Step out | the next line entered in a procedure that called this one: the rest of this one runs through |

With no program stopped, **F7** runs the program and stops before its
first line; **Ctrl+R** (*Run*) while one is stopped continues it, and
*Run > Stop* ends it. A step goes by **lines** as the runtime enters them:
the statements after `:` on a line run with it, and when a loop goes
round, the step stops at the first line of its body. The depth Step over
and Step out compare is the BASIC stack's: its procedures' frames and
its `{GOSUB}`s.

```basic
' F9 on the line of RETURN n * Fact(n - 1), Run: four breaks, the call
' stack one FUNCTION Fact deeper each time; F11 then goes back out
OPTION INTEGER
FUNCTION Fact(n)
  IF n <= 1 THEN RETURN 1
  RETURN n * Fact(n - 1)
END FUNCTION
PRINT "4! ="; Fact(4)
```

## The program's screen

When a program stops, its screen (its windows, the colours of its cards,
its palette, its sprites, its menu bar) is kept in a RAM bank and on
VERA's back screen, and its timers are held; Continue and the steps give
all of it back as it was (in about 60 ms) and its timers go on. While it
is stopped, the editor's menus and keys are the editor's, and its own
handlers do not run. Gate `vb_debug` compares a program's screen after a
break with the same program run without one, VERA's bytes and all.

A stopped program keeps its banks. New, Open and Quit wait until it has
ended (*Run > Stop*); Check and Format too.

## TRON and the trace

`{TRON}` in a program, or *Run > Trace (TRON)* for the whole of the next
runs, records each line the program enters: its number, or its line in
the text for a line without one. The editor keeps the last 200; **F12**
(*Run > The trace*) shows them in the pane, the newest at the bottom, each
with its line's text; PgUp and PgDn scroll, F12 or Esc closes it. `{TROFF}`
stops the recording. The lines are those `vbasic.py run --trace` writes
for the same program (`VB TRON n`), which gate `vb_debug` checks.

```basic
' the trace: 5, 6, 7, 6, 7, 6, 7, 8 (lines without numbers: their line
' in the text)
OPTION INTEGER
TRON
FOR i = 1 TO 3
  s = s + i
NEXT
TROFF
PRINT s
```

In *VeraBASIC Run*, `{TRON}` writes `TRON n` lines to the emulator's
console (`LogText`); on the X16 itself they go nowhere.

## Error messages

An error that stops the program is shown in the status bar and, whole, in
the pane at the right: its number and words, the line, the procedure it
happened in, and the statement as *Format* would write it:

    Error 13, Type mismatch, in line 8 (SUB Tick): total = n + name$

An error of a file or a folder has the kernel's own error after its
words (the number `{ERRFILE}` gives):

    Error 50, File not found (kernel 5), in line 4: OPEN #1, "No such file.txt", "r"

**F1** on that pane opens the error's help page (*Help > Error messages*
lists them all); Esc closes it. The console has the shorter form
(*Error 13, Type mismatch, in line 8*), which `{TRY}` ... `{CATCH}`,
`{ON}` `{ERROR}` `{GOTO}`, `{ERR}`, `{ERR$}` and `{ERL}` see.

*VeraBASIC Run* says it in its box when an error stops a program, in
lines that fit the box: the program's name, *Error 13 in line 8:* and
*Type mismatch* (the console's line may be under the program's windows).

## The debugger's memory

The debugger costs two RAM banks while VeraBASIC is open (its code on
the runtime's side, which also holds the trace, the breakpoints and the
values asked for, and the pane's code), one more while a program runs
(its names, record 0) and one more once it has stopped (its screen's
colours, its menu bar, its names in main RAM). With 512 KB, VeraBASIC
holds 31 banks when no program runs.
