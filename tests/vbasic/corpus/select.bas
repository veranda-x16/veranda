' SELECT CASE
OPTION INTEGER
FOR n = 0 TO 12
  SELECT CASE n
    CASE 0
      PRINT "zero"
    CASE 1, 2 TO 5, IS > 9
      PRINT "listed"
    CASE IS < 0
      PRINT "negative"
    CASE ELSE
      PRINT "other"
  END SELECT
NEXT
k$ = "e"
SELECT CASE k$
  ' a comment before the first CASE
  CASE "a", "e", "i", "o", "u": PRINT "vowel"
  CASE ELSE: PRINT "consonant"
END SELECT
SELECT CASE k$: CASE "x": PRINT "x": END SELECT
