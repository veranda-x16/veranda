' WHILE, REPEAT, DO with tests at the top and the bottom
n% = 1
WHILE n% < 100: n% = n% * 3: WEND
PRINT n%
WHILE 0: PRINT "never": WEND
n% = 0
REPEAT: n% = n% + 1: UNTIL n% >= 5
PRINT n%
DO WHILE n% > 0: n% = n% - 2: LOOP
PRINT n%
DO UNTIL n% >= 6: n% = n% + 4: LOOP
PRINT n%
DO: n% = n% - 1: LOOP WHILE n% > 3
PRINT n%
DO: n% = n% + 1: LOOP UNTIL n% = 9
PRINT n%
i% = 0
DO
  i% = i% + 1
  IF i% MOD 2 = 0 THEN PRINT i%;
LOOP UNTIL i% = 10
PRINT
