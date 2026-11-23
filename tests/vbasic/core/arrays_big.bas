' arrays across several RAM banks
OPTION MEMORY 12
DIM big(3000), ints%(10000)
FOR i% = 0 TO 3000: big(i%) = i% / 4: NEXT
FOR i% = 0 TO 10000: ints%(i%) = i% * 3: NEXT
s = 0: t = 0
FOR i% = 0 TO 3000 STEP 7: s = s + big(i%): NEXT
FOR i% = 0 TO 10000 STEP 11: t = t + ints%(i%): NEXT
PRINT s; t; big(3000); ints%(10000); ints%(5000)
DIM grid%(99, 99)
FOR y% = 0 TO 99: grid%(y%, y%) = y%: grid%(y%, 99 - y%) = -y%: NEXT
PRINT grid%(50, 50); grid%(50, 49); grid%(0, 99); grid%(99, 0)
