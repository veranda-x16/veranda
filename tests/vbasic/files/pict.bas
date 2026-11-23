' Pictures, icons, sprites, tiles and the clipboard (gate vb_files)
OPTION INTEGER
WINDOW #1, 2, 2, 76, 56, "Pictures", STATUS 2
ON CLOSE #1 CALL Bye
ball$ = PICTURE$(DATA)
DATA 16, 12
DATA ".....######.....", "...##########..."
DATA "..############..", ".##############."
DATA ".####..####..###", "################"
DATA "################", ".##############."
DATA ".###.######.###.", "..###......###.."
DATA "...##########...", ".....######....."
PRINT "ball"; LEN(ball$); ASC(ball$); ASC(MID$(ball$, 2))
t$ = PICTURE$("Run tile.txt")
PRINT "tile"; LEN(t$); ASC(t$); ASC(MID$(t$, 2))
WINDOW USE #1
BITMAP 8, 8, ball$
BITMAP 40, 8, t$
ICON 1, 96, 8, ball$, One
ICON 2, 128, 8, t$, Two
SPRITE 2, ball$
SPRITE 2 AT 200, 100
SPRITE 2 ON
TILE 2, 8, "AUTOSTART"
TILE 8, 8, "SHELL", SKY
TRY
  TILE 14, 8, "No such program"
CATCH
  PRINT "tile:"; ERR; ERRFILE
END TRY
TRY
  BITMAP 0, 0, "x"
CATCH
  PRINT "bitmap:"; ERR
END TRY
CLIPBOARD "Copied by VeraBASIC" + CHR$(10) + "a second line"
c$ = CLIPBOARD$
PRINT LEN(c$); " ["; LEFT$(c$, 19); "]"
CLIPBOARD PICTURE 8, 8, 23, 19
n = 0
WAIT EVENTS
SUB One
  n = n + 1
  PRINT "one"; n
  SPRITE 2 AT 200 + n * 20, 100
  IF n = 2 THEN ICON OFF 1
END SUB
SUB Two
  PRINT "two"
  SPRITE 2 OFF
  ICONS CLEAR
  END
END SUB
SUB Bye : END : END SUB
