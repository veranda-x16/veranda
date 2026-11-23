' Bird Watch, the application (DECISIONS V99): the tutorial's step 7
' with its APP lines, its own tile and its own documents (.brd files,
' a count of birds), made into an application by File > Make
' application... in VeraBASIC (or tools/vbasic.py app)
OPTION INTEGER
APP NAME "Bird Watch", CLASS "BirdWatch", VERSION "1.0", AUTHOR "Veranda"
APP DESCRIPTION "Counts the birds at the feeder."
APP DOCUMENTS "BRD"
APP TILE SKY
TILE DATA "................................", "................................"
TILE DATA "................................", "..............#####............."
TILE DATA "............##.....##...........", "...........#.........#.........."
TILE DATA "..........#...##......#.........", "..........#...##.......####....."
TILE DATA "..........#............#..##....", ".........#.................#...."
TILE DATA ".........#.............####.....", "........#..............#........"
TILE DATA ".......#...............#........", "......#................#........"
TILE DATA ".....#..######.........#........", "....#..#......##.......#........"
TILE DATA "...#..#.........#......#........", "..#..#...........#.....#........"
TILE DATA "..#.#.............#...#.........", "..##...............###.........."
TILE DATA "..#.................#...........", ".....................#.........."
TILE DATA "......................##........", ".......................#........"
TILE DATA "........######.....#...#........", ".............#.....#............"
TILE DATA ".............#.....#............", "............###...###..........."
TILE DATA "................................", ".##############################."
TILE DATA "................................", "................................"
WINDOW #1, 10, 6, 60, 40, "Bird Watch", CLOSE, FRAME, SHADOW, STATUS 2
WINDOW USE #1
FONT UI
TEXT 16, 20, "Birds at the feeder"
PAPER 0, 28, 60, 8, GREEN
PAPER 0, 3, 60, 25, SKY2
CARDS 40, 1, "Keys: B, C"
ON KEY CALL Typed
MENU "Bird Watch" : ITEM "About Bird Watch", About
MENU "File" : ITEM "Save the count", SaveCount, "S" : ITEM "Put aside", PutAside
  ITEM "Quit", DoQuit, "Q"
MENU "Birds" : ITEM "Add a bird", AddBird, "B" : ITEM "Start again", Reset
  ITEM "Sound", ToggleSound
CHECK "Sound", 1
withsound = 1
MENU SHOW
count = 0
doc$ = DOCUMENT$
IF doc$ <> "" THEN ReadCount
ShowCount
TIMER 1, 60 CALL Tick
ON CLICK CALL Clicked
ON CLOSE #1 CALL DoQuit
ON QUIT CALL DoQuit
ON CLOSE #2 CALL CloseAbout

SUB About
  WINDOW #2, 25, 18, 30, 8, "About", CLOSE, FRAME, SHADOW
  WINDOW USE #2
  FONT UI
  TEXT 12, 20, "Bird Watch 1.0"
  TEXT 12, 36, "Counts the birds at the feeder."
  WINDOW USE #1
END SUB

SUB CloseAbout
  WINDOW CLOSE #2
END SUB

SUB Clicked
  IF MOUSEB AND 128 THEN EXIT SUB
  IF HIT(#1, MOUSEX, MOUSEY) <> 4 THEN EXIT SUB
  DrawBird MOUSEX, MOUSEY
  AddBird
END SUB

SUB DrawBird(x, y)
  WINDOW USE #1
  BOX x - 3, y - 2, x + 3, y + 2
  LINE x - 8, y - 6, x, y
  LINE x, y, x + 8, y - 6
END SUB

SUB ToggleSound
  withsound = 1 - withsound
  CHECK "Sound", withsound
END SUB

SUB AddBird
  count = count + 1
  IF withsound THEN SOUND SND_OPEN
  IF withsound AND count MOD 5 = 0 THEN PLAY 0, "T200 O5 L16 C E G > C"
  ShowCount
END SUB

SUB Typed
  k$ = KEY$
  IF k$ = "b" THEN DrawBird 40 + count * 20, 100 : AddBird
  IF k$ = "c" THEN Reset
END SUB

SUB Reset
  WINDOW USE #1
  PATTERN 0 : BOX 0, 30, 470, 220 : PATTERN 1
  count = 0
  ShowCount
END SUB

SUB ShowCount
  WINDOW STATUS #1, STR$(count) + " birds", TIME$
END SUB

SUB Tick
  ShowCount
END SUB

SUB ReadCount
  TRY
    OPEN #1, doc$, "r"
    LINE INPUT #1, a$
    CLOSE #1
    count = VAL(a$)
  CATCH
    count = 0
  END TRY
END SUB

SUB SaveCount
  IF doc$ = "" THEN CHDIR FOLDER$(DOCS) : doc$ = "Sightings.brd"
  OPEN #1, doc$, "w"
  PRINT #1, count
  CLOSE #1
END SUB

SUB PutAside
  ASIDE
END SUB

SUB DoQuit
  SOUND OFF
  END
END SUB
