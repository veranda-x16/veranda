' Local and global names
total% = 100
i% = 5
Add 3
Report
PRINT total%, i%

SUB Add(n%)
  LOCAL i%
  FOR i% = 1 TO n%
    total% = total% + i%
  NEXT
END SUB

SUB Report
  SHARED total%
  LOCAL s$, i%
  s$ = "total: " + STR$(total%)
  i% = 0
  PRINT s$
END SUB
