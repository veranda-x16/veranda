' Address book: names, telephones and towns kept in a file of their own,
' read with INPUT #, written with PRINT #; a DIALOG to add an address.
' A VeraBASIC example (docs/vbasic/manual/extensions.md); MIT licence.
APP NAME "Address book"
OPTION INTEGER
DIM who$(40), tel$(40), town$(40)
n = 0
f$ = "Addresses of the people of the veranda.txt"
WINDOW #1, 4, 4, 72, 50, "Address book", STATUS 2, CLOSE
MENU "Address book" : ITEM "About Address book", About
MENU "File"
  ITEM "Add an address...", DoAdd, "A"
  ITEM "Save", DoSave, "S"
  ITEM "Quit", Done, "Q"
END MENU
MENU SHOW
ON CLOSE #1 CALL Done
WINDOW USE #1
FONT UI
LoadBook
ShowBook
WAIT EVENTS

SUB LoadBook
  TRY
    OPEN #1, f$, "r"
    WHILE NOT EOF(1) AND n < 40
      n = n + 1
      INPUT #1, who$(n), tel$(n), town$(n)
    WEND
    CLOSE #1
  CATCH
    IF ERR <> 50 THEN MSGBOX "The address book could not be read: " + ERR$
    CLOSE
  END TRY
END SUB

SUB ShowBook
  CLS
  STYLE BOLD
  TEXT 12, 16, "Name" : TEXT 220, 16, "Telephone" : TEXT 360, 16, "Town"
  STYLE 0
  LINE 8, 20, 540, 20
  FOR i = 1 TO n
    y = 20 + i * 14
    TEXT 12, y, who$(i) : TEXT 220, y, tel$(i) : TEXT 360, y, town$(i)
  NEXT
  WINDOW STATUS #1, f$, STR$(n) + " addresses"
END SUB

SUB About
  MSGBOX "Names, telephones and towns, in a file.", "Address book"
END SUB

SUB DoAdd
  a$ = "" : t$ = "" : c$ = ""
  DIALOG 18, 16, 44, 16
    LABEL 2, 2, "A new address"
    LABEL 2, 5, "Name:"
    FIELD 12, 5, a$, 30
    LABEL 2, 7, "Telephone:"
    FIELD 12, 7, t$, 16
    LABEL 2, 9, "Town:"
    FIELD 12, 9, c$, 24
    BUTTON OK
    BUTTON CANCEL
  END DIALOG
  IF DIALOG RESULT = 1 AND a$ <> "" AND n < 40 THEN
    n = n + 1
    who$(n) = a$ : tel$(n) = t$ : town$(n) = c$
    ShowBook
  END IF
END SUB

SUB DoSave
  OPEN #1, f$, "w"
  FOR i = 1 TO n
    PRINT #1, Q$(who$(i)); ","; Q$(tel$(i)); ","; Q$(town$(i))
  NEXT
  CLOSE #1
  WINDOW STATUS #1, "Saved", STR$(n) + " addresses"
END SUB

' a field in quotes (a comma in it stays)
FUNCTION Q$(s$)
  Q$ = CHR$(34) + s$ + CHR$(34)
END FUNCTION

SUB Done
  PRINT n; " addresses"
  END
END SUB
