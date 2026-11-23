' EXIT FOR and leaving loops
FOR i% = 1 TO 100
  IF i% * i% > 50 THEN EXIT FOR
NEXT
PRINT "stopped at"; i%
FOR i% = 1 TO 3
  FOR j% = 1 TO 100
    IF j% > i% THEN EXIT FOR
    PRINT i%; j%;
  NEXT
  PRINT
NEXT
n% = 0
WHILE n% < 100
  n% = n% + 1
  FOR k% = 1 TO 5
    IF n% = 4 THEN EXIT WHILE
  NEXT
WEND
PRINT "n"; n%
DO
  n% = n% + 1
  IF n% > 7 THEN EXIT DO
LOOP
PRINT "n"; n%
REPEAT
  n% = n% + 2
  IF n% > 12 THEN EXIT REPEAT
UNTIL 0
PRINT "n"; n%
