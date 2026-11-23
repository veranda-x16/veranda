' SELECT CASE: values, ranges, IS, strings, CASE ELSE
FOR n% = 0 TO 12
  SELECT CASE n%
    CASE 0
      PRINT n%; "zero"
    CASE 1, 2, 3
      PRINT n%; "small"
    CASE 4 TO 6
      PRINT n%; "middle"
    CASE IS > 10
      PRINT n%; "big"
    CASE ELSE
      PRINT n%; "other"
  END SELECT
NEXT
FOR i% = 1 TO 4
  READ w$
  SELECT CASE w$
    CASE "a", "e", "i", "o", "u": PRINT w$; " vowel"
    CASE "b" TO "d": PRINT w$; " b-d"
    CASE ELSE: PRINT w$; " other"
  END SELECT
NEXT
DATA "e", "c", "z", "u"
x = 2.5
SELECT CASE x
  CASE IS < 2: PRINT "under 2"
  CASE 2 TO 3: PRINT "2 to 3"
END SELECT
SELECT CASE 99
  CASE 1: PRINT "one"
END SELECT
PRINT "no case matched, on"
