' expect 5: NEXT without FOR
' expect 9: NEXT j% does not match FOR k% in line 8
FOR i% = 1 TO 3
NEXT
NEXT
x% = 1
FOR i% = 1 TO 3
  FOR k% = 1 TO 2
NEXT j%
NEXT k%
NEXT i%
