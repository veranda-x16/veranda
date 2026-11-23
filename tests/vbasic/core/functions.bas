' FUNCTION: results, RETURN, recursion, in expressions, strings
FUNCTION Area(w, h)
  Area = w * h
END FUNCTION
FUNCTION Fact(n)
  IF n <= 1 THEN Fact = 1 ELSE Fact = n * Fact(n - 1)
END FUNCTION
FUNCTION Fib%(n%)
  IF n% < 2 THEN RETURN n%
  RETURN Fib%(n% - 1) + Fib%(n% - 2)
END FUNCTION
FUNCTION Twice$(s$)
  Twice$ = s$ + s$
END FUNCTION
FUNCTION Zero%
  Zero% = 0
END FUNCTION
FUNCTION Early%(n%)
  Early% = -1
  IF n% < 0 THEN EXIT FUNCTION
  Early% = n% * 2
END FUNCTION
PRINT Area(3, 4); Area(2.5, 2)
PRINT Fact(10); Fact(12)
FOR i% = 0 TO 15: PRINT Fib%(i%);: NEXT: PRINT
PRINT Twice$("ab"); LEN(Twice$(Twice$("xyz")))
PRINT Zero%; Zero%() + 1
PRINT Early%(-5); Early%(21)
PRINT Area(Fact(3), Fib%(5)) + 1
