' Sketch: a full-screen program drawn with the mouse (gate vb_ui)
OPTION INTEGER
APP NAME "Sketch"
MENU "Sketch" : ITEM "Clear", DoClear : ITEM "Quit", DoQuit
MENU SHOW
SCREEN FULL "Untitled sketch"
POINTER CROSS
ON CLICK CALL Clicked
ON WHEEL CALL Turned
lastx = -1
size = 4
SUB Clicked
  PRINT "click"; MOUSEX; MOUSEY; MOUSEB
  IF MOUSEB AND 128 THEN EXIT SUB
  IF lastx >= 0 THEN LINE lastx, lasty, MOUSEX, MOUSEY
  BOX MOUSEX - size, MOUSEY - size, MOUSEX + size, MOUSEY + size
  lastx = MOUSEX : lasty = MOUSEY
  IF MOUSEIN(0, 16, 99, 115) THEN PRINT "top left corner"
END SUB
SUB Turned
  size = size + WHEEL
  IF size < 1 THEN size = 1
  PRINT "size"; size
END SUB
SUB DoClear : CLS : lastx = -1 : END SUB
SUB DoQuit : POINTER ARROW : END : END SUB
