' Menus: three menus, check marks, a disabled item, shortcuts (gate vb_ui)
OPTION INTEGER
APP NAME "Menus"
WINDOW #1, 10, 8, 60, 20, "Menus", STATUS 2
MENU "Menus" : ITEM "About Menus", About
MENU "Edit"
  ITEM "Cut", DoCut, "X"
  ITEM "Copy", DoCopy, "C"
  ITEM "-"
  ITEM "Bold", DoBold, "B"
END MENU
MENU "File" : ITEM "Save", DoSave, "S" : ITEM "Quit", DoQuit, "Q"
MENU SHOW
MENU ENABLE "Edit", "Cut", 0
isbold = 0
SUB About : WINDOW STATUS #1, "Menus, a VeraBASIC test", "" : PRINT "about" : END SUB
SUB DoCut : PRINT "cut" : END SUB
SUB DoCopy : PRINT "copy" : MENU ENABLE "Edit", "Cut", 1 : END SUB
SUB DoBold
  isbold = 1 - isbold
  CHECK "Bold", isbold
  PRINT "bold"; isbold
END SUB
SUB DoSave : PRINT "save" : END SUB
SUB DoQuit : PRINT "quit" : END : END SUB
