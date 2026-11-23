' FOR: integer and float, STEP, zero passes, nesting, NEXT with names
FOR i% = 1 TO 5: PRINT i%;: NEXT: PRINT
FOR i% = 10 TO 1 STEP -3: PRINT i%;: NEXT i%: PRINT
FOR i% = 1 TO 0: PRINT "never": NEXT: PRINT "after zero"; i%
FOR x = 0 TO 1 STEP 0.25: PRINT x;: NEXT: PRINT
FOR x = 1 TO 0 STEP -0.5: PRINT x;: NEXT: PRINT
FOR i% = 1 TO 3: FOR j% = 1 TO 3: PRINT i% * j%;: NEXT j%, i%: PRINT
FOR a% = 1 TO 2
  FOR b% = 1 TO 2
    PRINT a%; b%
  NEXT b%
NEXT a%
FOR i% = 32760 TO 32767: PRINT i%;: NEXT: PRINT
PRINT "i after"; i%
FOR k = 1 TO 3: NEXT: PRINT "k after"; k
FOR i% = 1 TO 3: FOR j% = 5 TO 1: PRINT "x": NEXT j%, i%: PRINT "j zero passes"; i%
n% = 3: FOR i% = 1 TO n%: n% = 10: PRINT i%;: NEXT: PRINT
