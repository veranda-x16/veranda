' put aside (Alt+Tab: TaskCtl) in the middle of a loop: it comes back
' and goes on counting
FOR i% = 1 TO 24
  FOR j% = 1 TO 1500: k = j% * 2.5: NEXT
  PRINT i%; k
NEXT
PRINT "still counting"
