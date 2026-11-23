' Keys: ON KEY, KEY$, KEYCODE, KEYMODS and a menu's shortcut (gate vb_ui)
OPTION INTEGER
WINDOW #1, 10, 10, 60, 20, "Type", STATUS 2
MENU "Keys" : ITEM "Save", DoSave, "S" : ITEM "Quit", DoQuit, "Q"
MENU SHOW
ON KEY CALL Typed
t$ = ""
SUB Typed
  PRINT "key"; KEYCODE; KEYMODS; " "; KEY$
  IF KEY$ = "q" THEN END
  IF KEYCODE = 13 THEN
    PRINT "line: "; t$
    t$ = ""
  ELSE
    t$ = t$ + KEY$
  END IF
  WINDOW STATUS #1, t$, STR$(LEN(t$))
END SUB
SUB DoSave : PRINT "saved "; t$ : END SUB
SUB DoQuit : END : END SUB
