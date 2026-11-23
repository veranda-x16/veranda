' VeraBASIC Run's console: a program to look at (the gate's screenshot)
OPTION INTEGER
PRINT "VeraBASIC Run: the console"
PRINT
FUNCTION Fact(n)
  IF n <= 1 THEN RETURN 1
  RETURN n * Fact(n - 1)
END FUNCTION
FOR i = 1 TO 7
  PRINT "Fact("; i; ") ="; Fact(i), "square root"; SQR(i)
NEXT
PRINT
DIM birds$(4)
FOR i = 0 TO 4: READ birds$(i): NEXT
DATA "Robin", "Wren", "Blue tit", "Jay", "Owl"
SELECT CASE LEN(birds$(2))
  CASE IS > 5: PRINT birds$(2); " has a long name"
  CASE ELSE: PRINT birds$(2)
END SELECT
TRY
  x = 1 / 0
CATCH
  PRINT "Caught: "; ERR$; " in line"; ERL
END TRY
FOR i = 0 TO 4: PRINT TAB(i * 6); birds$(i): NEXT
PRINT "Done."
