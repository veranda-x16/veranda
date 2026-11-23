# BASIC and back

You can leave Veranda for the X16's BASIC, and come back to the desktop
without loading Veranda again.

## Go to BASIC, keep Veranda

In the desktop choose **Options > BASIC (keep Veranda)**. Veranda plays
a sound and BASIC starts. Veranda stays in memory:

- BASIC has `$0801-$87FF` (32,767 bytes) and RAM banks 1 to 46 on a
  512 KB machine (1 to 238 with 2 MB). Veranda keeps the banks above.
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
