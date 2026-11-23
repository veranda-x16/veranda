' WHILE, REPEAT and DO
n% = 10
WHILE n% > 0
  n% = n% \ 2
  IF n% = 1 THEN EXIT WHILE
WEND
REPEAT
  n% = n% + 1
  IF n% = 99 THEN EXIT REPEAT
UNTIL n% >= 5
DO
  n% = n% - 1
LOOP UNTIL n% = 0
DO WHILE n% < 3
  n% = n% + 1
LOOP
DO UNTIL n% = 0: n% = n% - 1: LOOP
DO
  IF n% > 4 THEN EXIT DO
  n% = n% + 1
LOOP WHILE 1
WHILE 0: WEND
