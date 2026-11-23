' FUNCTIONs
PRINT Area(3, 4), Fib%(10), Twice$("ab"), Clamp%(-5)

FUNCTION Area(w, h)
  Area = w * h
END FUNCTION

FUNCTION Fib%(n%)
  IF n% < 2 THEN RETURN n%
  Fib% = Fib%(n% - 1) + Fib%(n% - 2)
END FUNCTION

FUNCTION Twice$(s$)
  RETURN s$ + s$
END FUNCTION

FUNCTION Clamp%(v%)
  Clamp% = v%
  IF v% >= 0 THEN EXIT FUNCTION
  Clamp% = 0
END FUNCTION
