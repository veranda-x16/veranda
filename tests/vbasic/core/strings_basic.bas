' strings: joining, the functions
a$ = "Robin": b$ = "Wren"
c$ = a$ + " and " + b$
PRINT c$; LEN(c$)
PRINT LEFT$(c$, 3); "|"; RIGHT$(c$, 4); "|"; MID$(c$, 7, 3); "|"; MID$(c$, 7)
PRINT LEFT$(c$, 0); "|"; LEFT$(c$, 100); "|"; RIGHT$(c$, 0); "|"; MID$(c$, 99); "|"
PRINT ASC("A"); ASC("a"); CHR$(66); CHR$(97) + CHR$(98)
PRINT STR$(12); STR$(-12); STR$(1.5); "|"; STR$(0)
PRINT VAL("12"); VAL(" 3.5"); VAL("-7e2"); VAL("x"); VAL("12abc"); VAL(".5")
PRINT "a" < "b"; "b" < "a"; "abc" = "abc"; "ab" < "abc"; "" < "a"; "B" < "a"
d$ = "": PRINT LEN(d$); "["; d$; "]"
e$ = c$: c$ = "changed": PRINT e$; " / "; c$
PRINT LEN(STR$(100)); LEN(SPC(5))
