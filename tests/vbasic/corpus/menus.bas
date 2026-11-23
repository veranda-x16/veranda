' Menus
MENU "Notes": ITEM "About Notes", About
MENU "Edit"
  ITEM "Cut", DoCut, "X"
  ITEM "Copy", DoCopy, "C"
  ITEM "-"
  ITEM "Bold", DoBold: CHECK "Bold", 1
END MENU
MENU SHOW
MENU ENABLE "Edit", "Cut", 0
WAIT EVENTS
SUB About: MSGBOX "Notes": END SUB
SUB DoCut: END SUB
SUB DoCopy: END SUB
SUB DoBold: CHECK "Bold", 0: END SUB
