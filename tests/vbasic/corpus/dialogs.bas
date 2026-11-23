' Dialogs
MSGBOX "Saved."
IF ASK("Discard changes?") THEN END
n$ = INPUTBOX$("Your name:")
n$ = INPUTBOX$("Size:", "12", 3)
f$ = FILEOPEN$("Open a list", "TXT")
g$ = FILESAVE$("Save as", "Birds 2026.txt")
s$ = "8"
DIALOG 20, 10, 30, 12
  LABEL 2, 2, "Size"
  FIELD 10, 2, s$, 3
  BUTTON OK: BUTTON CANCEL
END DIALOG
IF DIALOG RESULT = 1 THEN size% = VAL(s$)
DIALOG 20, 10, 20, 6: BUTTON OK: END DIALOG
