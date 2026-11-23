' The APP lines: the source's app.hdr
APP NAME "Bird Watch", CLASS "BirdWatch", VERSION "1.0", AUTHOR "Me"
APP DESCRIPTION "Counts the birds at the feeder."
APP DOCUMENTS "BRD", "TXT"
APP TILE SKY
TILE DATA "......####......", "....########....", "..############.."
APP STAY
APP CLASSIC
ON QUIT CALL AskQuit
WAIT EVENTS
SUB AskQuit
  IF ASK("Quit Bird Watch?") THEN END
END SUB
