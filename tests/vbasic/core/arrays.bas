' arrays: DIM, two and three dimensions, UBOUND, arrays without DIM
DIM a%(10), g(3, 4), s$(5), c%(2, 2, 2)
FOR i% = 0 TO 10: a%(i%) = i% * i%: NEXT
PRINT a%(10); UBOUND(a%); UBOUND(g, 1); UBOUND(g, 2); UBOUND(c%, 3)
FOR i% = 0 TO 3: FOR j% = 0 TO 4: g(i%, j%) = i% + j% / 10: NEXT j%, i%
PRINT g(3, 4); g(1, 2); g(0, 0)
FOR i% = 0 TO 5: s$(i%) = CHR$(65 + i%) + "x": NEXT
PRINT s$(0); s$(5)
c%(1, 2, 1) = 7: c%(2, 2, 2) = 8: PRINT c%(1, 2, 1) + c%(2, 2, 2); c%(0, 0, 0)
v(3) = 3.5: PRINT v(3); v(10); UBOUND(v)
w$(2) = "auto": PRINT w$(2); LEN(w$(9))
m%(1, 1) = 4: PRINT m%(1, 1); UBOUND(m%, 2)
TRY
  PRINT a%(11)
CATCH
  PRINT "error"; ERR; ERR$
END TRY
TRY
  DIM a%(5)
CATCH
  PRINT "error"; ERR; ERR$
END TRY
REDIM a%(3): PRINT UBOUND(a%); a%(3)
