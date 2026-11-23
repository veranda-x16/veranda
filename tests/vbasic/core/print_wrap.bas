' long lines wrap at the console's width (78 columns)
s$ = ""
FOR i% = 1 TO 10: s$ = s$ + "0123456789": NEXT
PRINT s$
PRINT LEFT$(s$, 78)
PRINT LEFT$(s$, 77); "xy"
FOR i% = 1 TO 30: PRINT i%;: NEXT: PRINT
FOR i% = 1 TO 9: PRINT "zone"; i%,: NEXT: PRINT
