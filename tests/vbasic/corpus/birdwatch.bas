' Bird Watch: the whole program (the plan's event model)
APP NAME "Bird Watch", CLASS "BirdWatch", VERSION "1.0"
OPTION INTEGER
WINDOW #1, 10, 6, 60, 40, "Bird Watch", CLOSE, FRAME, SHADOW, STATUS 2
MENU "Bird Watch": ITEM "About Bird Watch", About
MENU "File": ITEM "Open...", DoOpen, "O": ITEM "-": ITEM "Quit", DoQuit, "Q"
MENU SHOW
ON CLICK CALL Clicked
ON KEY CALL Typed
ON CLOSE #1 CALL DoQuit
TIMER 1, 60 CALL Tick ' once a second
WAIT EVENTS ' optional: falling off the end does the same

SUB Clicked
  IF MOUSEB AND 1 THEN PLOT MOUSEX, MOUSEY
END SUB
SUB Tick: WINDOW STATUS #1, "", TIME$: END SUB
SUB DoQuit: END: END SUB
SUB About: MSGBOX "Bird Watch 1.0", "About": END SUB
SUB DoOpen
  f$ = FILEOPEN$("Open a list", "BRD")
  IF f$ = "" THEN EXIT SUB
  WINDOW TITLE #1, f$
END SUB
SUB Typed
  IF KEYCODE = KEY_ESC THEN DoQuit
END SUB
