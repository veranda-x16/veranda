' The debugger's gate (vb_debug): VeraBASIC Run's box when an error stops
' a program whose windows hide the console (DECISIONS V97)
OPTION INTEGER
WINDOW #1, 4, 4, 72, 50, "Windows over the console", FRAME, SHADOW, STATUS 2
WINDOW USE #1
FONT UI
TEXT 16, 20, "A division by zero comes"
d = 0
PRINT 10 / d
