' expect 6: Cannot assign to constant W%
' expect 7: Cannot assign to constant YELLOW
' expect 8: Constant W% defined twice
' expect 9: Cannot assign to constant W%
CONST W% = 640
W% = 1
YELLOW = 2
CONST W% = 3
FOR W% = 1 TO 2: NEXT
