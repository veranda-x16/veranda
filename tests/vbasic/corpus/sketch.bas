' Sketch: draw with the mouse, colour the paper
APP NAME "Sketch", CLASS "Sketch", VERSION "1.0"
OPTION INTEGER
SCREEN FULL "Sketch"
MENU "Sketch": ITEM "About Sketch", About
MENU "File": ITEM "Clear", DoClear, "N": ITEM "Save...", DoSave, "S": ITEM "Quit", DoQuit, "Q"
MENU "Colour": ITEM "Yellow", PickYellow: ITEM "Sky", PickSky
MENU SHOW
colour = YELLOW
lastx = -1
ON CLICK CALL Clicked
ON KEY CALL Typed
WAIT EVENTS

SUB Clicked
  IF MOUSEB AND 128 THEN lastx = -1: EXIT SUB
  IF lastx >= 0 THEN
    LINE lastx, lasty, MOUSEX, MOUSEY
  ELSE
    PLOT MOUSEX, MOUSEY
  END IF
  lastx = MOUSEX: lasty = MOUSEY
  PAPER MOUSEX \ 8, MOUSEY \ 8, 1, 1, colour
END SUB
SUB Typed
  IF KEY$ = "c" THEN DoClear
END SUB
SUB DoClear: CLS: END SUB
SUB PickYellow: colour = YELLOW: END SUB
SUB PickSky: colour = SKY: END SUB
SUB About: MSGBOX "Sketch 1.0": END SUB
SUB DoSave
  f$ = FILESAVE$("Save the sketch", "Sketch.txt")
  IF f$ = "" THEN EXIT SUB
  TRY
    OPEN #1, f$, "w"
    PRINT #1, "sketch"
    CLOSE #1
  CATCH
    MSGBOX "Not saved: " + ERR$
  END TRY
END SUB
SUB DoQuit: END: END SUB
