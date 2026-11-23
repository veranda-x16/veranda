' Counting: put aside in the middle of its loop, it goes on counting (gate vb_ui)
OPTION INTEGER
WINDOW #1, 20, 20, 40, 10, "Counting", STATUS 2
TIMER 1, 30 CALL Tick
n = 0
FOR i = 1 TO 30000
  n = n + 1
  IF n MOD 1000 = 0 THEN PRINT "count"; n : DOEVENTS
NEXT
PRINT "counted"; n
END
SUB Tick : WINDOW STATUS #1, STR$(n), "" : END SUB
