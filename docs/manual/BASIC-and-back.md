# BASIC and back

You can leave Veranda for the X16's BASIC, and come back to the desktop
without loading Veranda again.

## Go to BASIC, keep Veranda

In the desktop choose **Options > BASIC (keep Veranda)**. Veranda plays
a sound and BASIC starts. Veranda stays in memory:

- BASIC has `$0801-$87FF` (32,767 bytes) and RAM banks 1 to 43 on a
  512 KB machine (1 to 235 with 2 MB). Veranda keeps the banks above.
- The current folder is the system folder, `/VERANDA`.
- Programs that were put aside with Alt+Tab are lost: quit them first.

## Come back

Type:

    SYS 35328

or, in `/VERANDA`:

    LOAD"RBOOT"
    RUN

The desktop comes back, in the folder it showed. (The program that ran
before is not resumed, and files were closed.)

- `SYS 35328` needs Veranda's small return routine to be intact.
- `RBOOT` also works when BASIC or a program overwrote Veranda's main
  part: it restores Veranda from its copy in RAM, without the card.
- If the copy in RAM was overwritten too, `SYS 35328` says so, and
  `RBOOT` loads `VERANDA.PRG` from the card instead.

## Run a program from the desktop

Double-click a `.PRG` file in a folder window (or select it and choose
**File > Open**). Veranda asks:

    Run GAME.PRG?
    BASIC runs it, and Veranda
    comes back when it ends.

Choose **OK** to run it, **Cancel** to stay on the desktop. With OK:

1. Veranda goes to BASIC and stays in memory, as with
   **BASIC (keep Veranda)**.
2. BASIC goes to the program's folder, loads the program and runs it.
   Programs that load their own files (levels, pictures, music) find
   them next to the program.
3. When the program ends and BASIC shows `READY.` again, BASIC loads
   `RBOOT` and the desktop comes back, showing the program's folder.

You see each line BASIC is given on its screen: Veranda types them with
BASIC's `EXEC` command.

What runs this way:

- **BASIC programs** saved as `.PRG`.
- **Machine-code programs that start with a BASIC line** such as
  `10 SYS2061` (most X16 games and tools are made like this) and that
  go back to BASIC when they end.

What does not:

- **Files that load somewhere else than `$0801`**: Veranda says
  "BASIC cannot RUN this: it loads elsewhere." Load and start them
  yourself from BASIC, as their instructions say.
- **Programs over 38,657 bytes**: too big to load beside Veranda.
- **`VERANDA.PRG`** itself.

Things to know:

- A program has BASIC's memory and RAM banks 1 to 43 (512 KB), as
  above. Veranda's copy and the lines that bring it back are in the
  banks above that.
- If the program stops with a BASIC error, the desktop comes back all
  the same.
- Programs that were put aside with Alt+Tab are lost: the question says
  so ("Programs put aside are lost") when there are any.
- **If the desktop does not come back** (the program never returns to
  BASIC, it resets the X16, or it used all of the RAM banks), type
  `SYS 35328`, or:

      DOS"CD:/VERANDA"
      LOAD"RBOOT"
      RUN

  If a program overwrote the banks Veranda keeps, BASIC may also show a
  line of odd characters or an error first; `RBOOT` then loads
  `VERANDA.PRG` from the card. After a reset, start Veranda as usual.

## Quit Veranda completely

**Options > Quit Veranda** frees everything: BASIC gets all of its
memory, as at power-on. To start Veranda again:

    DOS"CD:VERANDA"
    BOOT

## Run a BASIC program from Veranda Claude or Ask

[Veranda Claude](Veranda-Claude.md) and [Veranda Ask](Veranda-Ask.md)
can save a BASIC program as a `.PRG`. Go to BASIC (keep Veranda), then:

    LOAD"/DOCUMENTS/GAME.PRG"
    RUN

and come back with `SYS 35328`.
