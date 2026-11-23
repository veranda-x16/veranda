' a big string array kept alive across many collections
DIM keep$(200)
FOR i% = 0 TO 200: keep$(i%) = "k" + STR$(i% * 7): NEXT
s% = 0
FOR r% = 1 TO 300
  a$ = keep$(r% MOD 201) + "-" + keep$((r% * 3) MOD 201)
  b$ = a$ + a$ + a$
  s% = (s% + LEN(b$) + ASC(MID$(b$, 2, 1))) MOD 30000
NEXT
PRINT s%
PRINT keep$(0); keep$(100); keep$(200)
