' The debugger's gate (vb_debug): an error's message, its statement
' quoted in canonical form, the line and the procedure; then a kernel's
' error (a file that is not there) with the kernel's code
OPTION INTEGER
name$ = "Bird"
SUB Tick(n)
  PRINT "tick"; n
  total   =n+   name$
END SUB
Tick 5
