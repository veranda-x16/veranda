' Notes: a small notebook. Lines of text, Open and Save with long names
' (FILEOPEN$, FILESAVE$), the clipboard (CLIPBOARD, CLIPBOARD$).
' A VeraBASIC example (docs/vbasic/manual/extensions.md); MIT licence.
APP NAME "Notes"
OPTION INTEGER
DIM lines$(30)
n = 0
file$ = "(not saved)"
changed = 0
WINDOW #1, 4, 4, 72, 50, "Notes", STATUS 2, CLOSE
MENU "Notes" : ITEM "About Notes", About
MENU "File"
  ITEM "New", DoNew, "N"
  ITEM "Open...", DoOpen, "O"
  ITEM "Save as...", DoSave, "S"
  ITEM "Quit", DoQuit, "Q"
END MENU
MENU "Edit"
  ITEM "Add a line...", DoAdd, "A"
  ITEM "Copy all", DoCopy, "C"
  ITEM "Paste", DoPaste, "V"
END MENU
MENU SHOW
ON CLOSE #1 CALL DoQuit
WINDOW USE #1
FONT UI
Redraw
WAIT EVENTS

SUB Redraw
  CLS
  FOR i = 1 TO n
    TEXT 12, i * 14 + 4, lines$(i)
  NEXT
  WINDOW STATUS #1, file$, STR$(n) + " lines"
END SUB

SUB About
  MSGBOX "A notebook in VeraBASIC." + CHR$(10) + "Lines, files and the clipboard.", "Notes"
END SUB

SUB AddLine(t$)
  IF n < 30 THEN
    n = n + 1
    lines$(n) = t$
    changed = 1
  END IF
END SUB

SUB DoAdd
  t$ = INPUTBOX$("A line for the notes:", "", 60)
  IF t$ <> "" THEN AddLine t$ : Redraw
END SUB

SUB DoNew
  n = 0
  file$ = "(not saved)"
  changed = 0
  Redraw
END SUB

SUB DoSave
  f$ = FILESAVE$("Save the notes as", "Notes from the veranda.txt")
  IF f$ = "" THEN EXIT SUB
  OPEN #1, f$, "w"
  FOR i = 1 TO n
    PRINT #1, lines$(i)
  NEXT
  CLOSE #1
  file$ = f$
  changed = 0
  Redraw
END SUB

SUB DoOpen
  f$ = FILEOPEN$("Open notes", "TXT")
  IF f$ = "" THEN EXIT SUB
  n = 0
  OPEN #1, f$, "r"
  WHILE NOT EOF(1) AND n < 30
    LINE INPUT #1, t$
    AddLine t$
  WEND
  CLOSE #1
  file$ = f$
  changed = 0
  Redraw
END SUB

SUB DoCopy
  t$ = ""
  FOR i = 1 TO n
    IF LEN(t$) + LEN(lines$(i)) < 250 THEN t$ = t$ + lines$(i) + CHR$(10)
  NEXT
  CLIPBOARD t$
  WINDOW STATUS #1, "Copied", STR$(LEN(t$)) + " characters"
END SUB

SUB DoPaste
  t$ = CLIPBOARD$
  WHILE t$ <> ""
    k = 1
    WHILE k <= LEN(t$) AND MID$(t$, k, 1) <> CHR$(10)
      k = k + 1
    WEND
    AddLine LEFT$(t$, k - 1)
    t$ = MID$(t$, k + 1)
  WEND
  Redraw
END SUB

SUB DoQuit
  IF changed THEN
    IF ASK("Quit without saving?") = 0 THEN EXIT SUB
  END IF
  END
END SUB
