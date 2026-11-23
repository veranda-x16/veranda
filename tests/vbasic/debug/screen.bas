' The debugger's gate (vb_debug): a program's screen, the same before and
' after a break. Menus, a window, coloured cards, patterns, a palette entry,
' a sprite, a running timer; the break is at "total = 0"
OPTION INTEGER
APP NAME "Screen"
MENU "Screen" : ITEM "About", About
MENU "Tools" : ITEM "Beep", Bp, "B"
MENU SHOW
WINDOW #1, 2, 3, 76, 54, "The screen kept", FRAME, SHADOW, STATUS 2
WINDOW USE #1
FOR i = 0 TO 5
  PAPER i * 12 + 1, 1, 11, 3, 6 + i
  CARDS i * 12 + 1, 2, " card" + STR$(i)
NEXT
FOR p = 0 TO 11
  PATTERN p
  BOX p * 48 + 8, 80, p * 48 + 48, 120
  FRAME p * 48 + 8, 80, p * 48 + 48, 120
NEXT
PATTERN 1
PALETTE 12, $F80
PAPER 60, 40, 14, 6, 12
FONT UI
TEXT 40, 160, "A window, cards, patterns, a sprite"
d$ = PICTURE$(DATA)
DATA 24, 21
DATA "########################", "#......................#", "#..####..........####..#"
DATA "#..####..........####..#", "#......................#", "#......................#"
DATA "#.........####.........#", "#.........####.........#", "#......................#"
DATA "#......................#", "#..####..........####..#", "#..####..........####..#"
DATA "#......................#", "#......................#", "#......................#"
DATA "#......................#", "#......................#", "#......................#"
DATA "#......................#", "#......................#", "########################"
SPRITE 2, d$
SPRITE 2 AT 400, 300
SPRITE 2 ON
ticks = 0
TIMER 1, 20 CALL Tick
WINDOW STATUS #1, "A break and back", "the same screen"
total = 0
FOR i = 1 TO 10
  total = total + i
NEXT
TEXT 40, 200, "total" + STR$(total)
WAIT EVENTS

SUB Tick
  ticks = ticks + 1
  IF ticks = 6 THEN PRINT "ticks"; ticks
END SUB

SUB About
  MSGBOX "The debugger's screen test"
END SUB

SUB Bp
  BEEP
END SUB
