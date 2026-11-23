' Bird Watch from the lake: a program document (vbasic.py build), opened
' by a double click in the shell (gate vb_tok)
OPTION INTEGER
DATA "Robin", 3, "Blue tit", 5, "Wren", 1, "Magpie", 2
total = 0
FOR i = 1 TO 4
  READ bird$, n
  PRINT bird$; TAB(12); n
  total = total + n
NEXT i
PRINT "Birds counted:"; total
PRINT "Average:"; total / 4
