' DATA, READ, RESTORE: numbers, strings, quotes, RESTORE to a line
READ a%, b, c$
PRINT a%; b; c$
READ d$, e$: PRINT "["; d$; "]["; e$; "]"
READ f, g%: PRINT f; g%
RESTORE
READ a%: PRINT a%
RESTORE 100
READ x$: PRINT x$
TRY
  READ y$, y$, y$
CATCH
  PRINT "error"; ERR; ERR$
END TRY
DATA 12, 3.5, plain text
DATA "with, comma", "  spaced  "
DATA 1E2, -7
100 DATA "from 100", second
