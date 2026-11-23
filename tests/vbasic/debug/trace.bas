' The debugger's gate (vb_debug): TRON's trace, more lines than the pane's
' 200, a GOSUB, a SUB and line numbers among them; the trace pane must end
' as tools/vbasic.py run --trace does
OPTION INTEGER
n = 0
c = 0
TRON
FOR i = 1 TO 60
  n = n + i
  IF n MOD 3 = 0 THEN GOSUB Three
  Count i
NEXT
TROFF
PRINT n; c
END
Three:
c = c + 1
RETURN
SUB Count(k)
  IF k = 60 THEN GOTO 1000
  EXIT SUB
1000 PRINT "the last"
END SUB
