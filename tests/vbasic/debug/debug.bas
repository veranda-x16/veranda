' The debugger's gate (vb_debug): breakpoints, steps, the variables (a
' procedure's locals, globals, arrays), watches, an edit, the call stack
' (a FUNCTION in itself), STOP, a GOSUB
OPTION INTEGER
DIM squares(5), grid(2, 3)
total = 0
name$ = "feeder"
FOR i = 1 TO 5
  squares(i) = i * i
  total = total + squares(i)
NEXT
grid(1, 2) = 12
SUB Twice(n)
  LOCAL k
  k = n * 2
  PRINT "Twice"; n; k
END SUB
FUNCTION Fact(n)
  IF n <= 1 THEN RETURN 1
  RETURN n * Fact(n - 1)
END FUNCTION
Twice total
PRINT "Fact"; Fact(4)
STOP
PRINT "Total:"; total; " at the "; name$
GOSUB Done
END
Done:
PRINT "done"
RETURN
