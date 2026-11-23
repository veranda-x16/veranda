' Arrays
DIM a%(100), grid$(10, 10), cube(3, 3, 3)
a%(0) = 1
grid$(2, 3) = "x"
cube(1, 2, 3) = 1.5
PRINT UBOUND(a%), UBOUND(grid$, 2)
REDIM a%(200)
n% = 5
REDIM list$(n% * 2)
FOR i% = 0 TO UBOUND(list$): list$(i%) = STR$(i%): NEXT
