' SUBs: parameters, BYREF, arrays, recursion
DIM a%(10)
x% = 1
y% = 2
Swap x%, y%
CALL Swap(x%, y%)
Fill a%(), 7
Greet "Robin"
CALL Greet("Wren")
Countdown 3
PRINT x%, y%, a%(3)

SUB Swap(BYREF p%, BYREF q%)
  LOCAL t%
  t% = p%: p% = q%: q% = t%
END SUB

SUB Fill(arr%(), v%)
  LOCAL i%
  FOR i% = 0 TO UBOUND(arr%)
    arr%(i%) = v%
  NEXT
END SUB

SUB Greet(who$)
  PRINT "Hello, "; who$
END SUB

SUB Countdown(n%)
  IF n% = 0 THEN EXIT SUB
  PRINT n%
  Countdown n% - 1
END SUB
