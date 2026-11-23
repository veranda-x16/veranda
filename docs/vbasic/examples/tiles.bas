' Tiles: a launcher's page. The programs of a folder (DIR$) as the shell
' shows them, each its tile (TILE) and its name; a click on one says
' which it is. Starting it is the shell's (the dock, the desktop).
' A VeraBASIC example (docs/vbasic/manual/extensions.md); MIT licence.
APP NAME "Tiles"
OPTION INTEGER
WINDOW #1, 2, 2, 76, 40, "Tiles", STATUS 2, CLOSE
WINDOW USE #1
ON CLOSE #1 CALL Done
DIM app$(12)
n = 0
f$ = DIR$("*.cvt")
WHILE f$ <> "" AND n < 12
  n = n + 1
  app$(n) = LEFT$(f$, LEN(f$) - 4)
  f$ = DIR$()
WEND
FOR i = 1 TO n
  TILE TileX(i), TileY(i), app$(i)
  CARDS TileX(i) - 2, TileY(i) + 5, LEFT$(app$(i), 8)
NEXT
WINDOW STATUS #1, CURDIR$, STR$(n) + " programs"
ON CLICK CALL Clicked
WAIT EVENTS

' the tile of program i: its card and row in the window
FUNCTION TileX(i)
  TileX = 3 + ((i - 1) MOD 6) * 12
END FUNCTION
FUNCTION TileY(i)
  TileY = 2 + ((i - 1) \ 6) * 9
END FUNCTION

SUB Clicked
  IF MOUSEB AND 128 THEN EXIT SUB
  FOR i = 1 TO n
    x = TileX(i) * 8
    y = TileY(i) * 8
    IF MOUSEX >= x AND MOUSEX < x + 32 AND MOUSEY >= y AND MOUSEY < y + 32 THEN
      PRINT "chose "; app$(i)
      MSGBOX app$(i), "Tiles"
    END IF
  NEXT
END SUB

SUB Done
  END
END SUB
