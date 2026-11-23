' Busy: a menu opened while BASIC runs a long loop (gate vb_ui)
OPTION INTEGER
WINDOW #1, 20, 20, 40, 10, "Busy", STATUS 2
MENU "Busy" : ITEM "Hello", Hello : ITEM "Quit", DoQuit
MENU SHOW
n = 0
FOR i = 1 TO 40
  FOR j = 1 TO 800 : n = n + 1 : NEXT
  PRINT "loop"; i
  IF i MOD 10 = 0 THEN DOEVENTS
NEXT
PRINT "loop done"
SUB Hello : PRINT "hello at"; n : END SUB
SUB DoQuit : END : END SUB
