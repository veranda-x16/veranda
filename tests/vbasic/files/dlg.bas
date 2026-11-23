' Dialogs: MSGBOX, ASK, INPUTBOX$, a DIALOG block (gate vb_files)
OPTION INTEGER
WINDOW #1, 2, 2, 76, 56, "Dialogs"
MSGBOX "Hello from a box." + CHR$(10) + "A second line.", "A title"
a = ASK("Is this a question?")
PRINT "ask"; a
n$ = INPUTBOX$("Your name:", "Robin", 20)
PRINT "name "; n$
c$ = INPUTBOX$("Cancelled:")
PRINT "cancel ["; c$; "]"
nm$ = "Wren"
tw$ = ""
DIALOG 20, 15, 40, 14
  LABEL 2, 2, "Name:"
  FIELD 10, 2, nm$, 20
  LABEL 2, 5, "Town:"
  FIELD 10, 5, tw$, 20
  BUTTON OK
  BUTTON CANCEL
END DIALOG
PRINT DIALOG RESULT; " "; nm$; " / "; tw$
END
