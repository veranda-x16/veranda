' expect 6: WEND without WHILE
' expect 12: UNTIL without REPEAT
' expect 14: LOOP without DO
' expect 17: NEXT missing for FOR in line 16
'
WEND
x = 0
WHILE x < 3
  FOR i = 1 TO 2
NEXT
WEND
UNTIL x = 1
DO
LOOP: LOOP
REPEAT
  FOR j = 1 TO 2
UNTIL j
