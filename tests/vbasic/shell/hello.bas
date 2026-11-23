' Hello from VeraBASIC on the card: a .BAS source that VeraBASIC Run
' tokenizes and prepares itself (gate vb_tok)
SUB Greet(who$, times%)
  LOCAL k%
  FOR k% = 1 TO times%
    PRINT "Hello, "; who$; "!"; k%
  NEXT k%
END SUB
Greet "card", 2
x = 1.5E3 / 4
PRINT "x ="; x; " and a third:"; 1 / 3
PRINT LEFT$("VeraBASIC Run", 9); " says goodbye"
