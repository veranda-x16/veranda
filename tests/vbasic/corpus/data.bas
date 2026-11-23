' DATA, READ and RESTORE
READ n%
FOR i% = 1 TO n%
  READ b$
  PRINT b$
NEXT
RESTORE Birds
READ n%
RESTORE
DATA 3, "Robin", "Wren", "Blue tit"
Birds:
DATA 2,Sparrow , "Rook, the black one"
DATA
DATA ,,
x% = 1: DATA 9: PRINT x%
