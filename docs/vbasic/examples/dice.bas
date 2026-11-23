' Dice: two dice to throw with an icon; a die as a sprite rolls across,
' sounds as they fall. ICON, PICTURE$, SPRITE, PLAY, SOUND.
' A VeraBASIC example (docs/vbasic/manual/extensions.md); MIT licence.
APP NAME "Dice"
OPTION INTEGER
WINDOW #1, 10, 6, 60, 40, "Dice", STATUS 2, CLOSE
WINDOW USE #1
ON CLOSE #1 CALL Done
throw$ = PICTURE$(DATA)
DATA 40, 14
DATA ".######################################.", "#......................................#"
DATA "#......................................#", "#......................................#"
DATA "#.........###.#.#.##..###.#.#..........#", "#..........#..#.#.#.#.#.#.#.#..........#"
DATA "#..........#..###.##..#.#.#.#..........#", "#..........#..#.#.#.#.#.#.###..........#"
DATA "#..........#..#.#.#.#.###.#.#..........#", "#......................................#"
DATA "#......................................#", "#......................................#"
DATA "#......................................#", ".######################################."
die$ = PICTURE$(DATA)
DATA 24, 21
DATA "..####################..", ".#....................#.", ".#....................#."
DATA ".#...###........###...#.", ".#...###........###...#.", ".#...###........###...#."
DATA ".#....................#.", ".#....................#.", ".#....................#."
DATA ".#........###.........#.", ".#........###.........#.", ".#........###.........#."
DATA ".#....................#.", ".#....................#.", ".#....................#."
DATA ".#...###........###...#.", ".#...###........###...#.", ".#...###........###...#."
DATA ".#....................#.", ".#....................#.", "..####################.."
ICON 1, 16, 16, throw$, Throw
SPRITE 2, die$
FONT UI
TEXT 80, 27, "Click Throw to throw the dice."
throws = 0
total = 0
WAIT EVENTS

' die k (1 or 2) showing v
SUB Face(k, v)
  x = 40 + (k - 1) * 120
  y = 60
  PATTERN 0 : BOX x, y, x + 63, y + 63
  FRAME x, y, x + 63, y + 63
  FRAME x + 2, y + 2, x + 61, y + 61
  PATTERN 1
  IF v = 1 OR v = 3 OR v = 5 THEN Pip x + 28, y + 28
  IF v >= 2 THEN Pip x + 10, y + 10 : Pip x + 46, y + 46
  IF v >= 4 THEN Pip x + 46, y + 10 : Pip x + 10, y + 46
  IF v = 6 THEN Pip x + 10, y + 28 : Pip x + 46, y + 28
END SUB

SUB Pip(x, y)
  BOX x, y, x + 7, y + 7
END SUB

SUB Throw
  SOUND SND_MENU
  SPRITE 2 ON
  FOR i = 0 TO 8
    SPRITE 2 AT 200 + i * 24, 150 + (i MOD 2) * 6
    SLEEP 2
  NEXT
  SPRITE 2 OFF
  a = INT(RND(1) * 6) + 1
  b = INT(RND(1) * 6) + 1
  Face 1, a
  Face 2, b
  PLAY 0, "T240 O5 C16 E16 G16"
  throws = throws + 1
  total = total + a + b
  WINDOW STATUS #1, "Threw " + STR$(a) + " and" + STR$(b), STR$(throws) + " throws, total" + STR$(total)
  PRINT "throw"; throws; a; b
  IF a = b THEN MSGBOX "A double!", "Dice"
END SUB

SUB Done
  PRINT "thrown"; throws; " times, total"; total
  END
END SUB
