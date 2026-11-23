' String functions
s$ = "Blackbird"
PRINT LEFT$(s$, 5), RIGHT$(s$, 4), MID$(s$, 6), MID$(s$, 2, 3)
PRINT LEN(s$), ASC(s$), CHR$(65), STR$(42), VAL("12.5")
t$ = s$ + CHR$(34) + STR$(LEN(s$))
PRINT t$
