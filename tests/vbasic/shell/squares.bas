' Squares and a table of them: a program document in a folder (gate
' vb_tok); VeraBASIC Run is found by its class in the top folder
FUNCTION Square(n)
  Square = n * n
END FUNCTION
n% = 1
WHILE n% <= 5
  PRINT n%; Square(n%); SQR(Square(n%) + 1)
  n% = n% + 1
WEND
SELECT CASE Square(3)
  CASE 9 : PRINT "nine"
  CASE ELSE : PRINT "not nine"
END SELECT
