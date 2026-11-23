' SUB: arguments by value, BYREF, CALL, recursion, EXIT SUB
SUB Greet(who$, times%)
  LOCAL i%
  FOR i% = 1 TO times%: PRINT "Hello, "; who$: NEXT
END SUB
SUB Swap(BYREF a%, BYREF b%)
  LOCAL t%
  t% = a%: a% = b%: b% = t%
END SUB
SUB Count(n%)
  IF n% = 0 THEN EXIT SUB
  PRINT n%;
  Count n% - 1
END SUB
SUB NoArgs
  PRINT "no arguments"
END SUB
Greet "Robin", 2
CALL Greet("Wren", 1)
x% = 1: y% = 2: Swap x%, y%: PRINT x%; y%
Count 5: PRINT
CALL NoArgs
NoArgs
v% = 7: Change v%: PRINT v%
SUB Change(n%)
  n% = 99
END SUB
