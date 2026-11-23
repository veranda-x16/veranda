' Notes: open and save with long names, the clipboard
APP NAME "Notes", CLASS "Notes", VERSION "1.0"
APP DOCUMENTS "TXT"
DIM line$(200)
count% = 0
WINDOW #1, 4, 4, 72, 50, "Notes", CLOSE, FRAME, STATUS 1
MENU "Notes": ITEM "About Notes", About
MENU "File": ITEM "Open...", DoOpen, "O": ITEM "Save as...", DoSave, "S": ITEM "Quit", DoQuit, "Q"
MENU "Edit": ITEM "Copy all", DoCopy, "C": ITEM "Paste", DoPaste, "V"
MENU SHOW
ON CLOSE #1 CALL DoQuit
IF DOCUMENT$ <> "" THEN Load DOCUMENT$
WAIT EVENTS

SUB Load(f$)
  TRY
    OPEN #1, f$, "r"
    count% = 0
    WHILE NOT EOF(1) AND count% <= UBOUND(line$)
      LINE INPUT #1, line$(count%)
      count% = count% + 1
    WEND
    CLOSE #1
    WINDOW TITLE #1, f$
    Redraw
  CATCH
    MSGBOX "Could not open " + f$ + ": " + ERR$
  END TRY
END SUB
SUB Redraw
  LOCAL i%
  WINDOW USE #1
  CLS
  FOR i% = 0 TO count% - 1
    CARDS 0, i%, line$(i%)
  NEXT
  WINDOW STATUS #1, STR$(count%) + " lines", ""
END SUB
SUB DoOpen
  f$ = FILEOPEN$("Open a note", "TXT")
  IF f$ <> "" THEN Load f$
END SUB
SUB DoSave
  LOCAL i%
  f$ = FILESAVE$("Save the note as", "A note with a long name.txt")
  IF f$ = "" THEN EXIT SUB
  OPEN #1, f$, "w"
  FOR i% = 0 TO count% - 1: PRINT #1, line$(i%): NEXT
  CLOSE #1
END SUB
SUB DoCopy
  LOCAL i%, all$
  FOR i% = 0 TO count% - 1: all$ = all$ + line$(i%) + CHR$(10): NEXT
  CLIPBOARD all$
END SUB
SUB DoPaste
  line$(count%) = CLIPBOARD$: count% = count% + 1: Redraw
END SUB
SUB About: MSGBOX "Notes 1.0", "About": END SUB
SUB DoQuit: END: END SUB
