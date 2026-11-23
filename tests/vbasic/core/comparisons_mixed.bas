' comparisons of integers with floats, strings with strings
FOR i% = -2 TO 2
  PRINT i%; i% < 0.5; i% = 1.0; i% > -1.5
NEXT
a$ = "apple": b$ = "apricot"
PRINT a$ < b$; a$ = LEFT$(b$, 2) + "ple"; b$ > a$; a$ <> b$
PRINT "Z" < "a"; "" = ""; " " > ""
