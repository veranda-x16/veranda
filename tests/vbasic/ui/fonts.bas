' Fonts: the UI font, the system font, styles, widths, cards (gate vb_ui)
OPTION INTEGER
WINDOW #1, 4, 4, 72, 50, "Fonts and text", FRAME
WINDOW USE #1
y = 20
FONT UI
TEXT 10, y, "Veranda UI, plain" : y = y + FONTHEIGHT + 4
STYLE BOLD
TEXT 10, y, "Veranda UI, bold" : y = y + FONTHEIGHT + 4
STYLE ITALIC
TEXT 10, y, "Veranda UI, italic" : y = y + FONTHEIGHT + 4
STYLE UNDERLINE + BOLD
TEXT 10, y, "Bold and underlined" : y = y + FONTHEIGHT + 4
STYLE 0
FONT SYSTEM
TEXT 10, y, "The system font" : y = y + FONTHEIGHT + 4
FONT "Veranda UI", 12
w = TEXTWIDTH("Centred in the window")
TEXT (576 - w) \ 2, y + 10, "Centred in the window"
PRINT "widths"; TEXTWIDTH("i"); TEXTWIDTH("W"); w
TRY
  FONT "No such font", 10
CATCH
  PRINT "error"; ERR; " "; ERR$
END TRY
CARDS 2, 20, "CARDS: the ROM's 8 x 8 font"
CARDS 2, 22, "reverse", REVERSE
CARDS 2, 24, "bold", BOLD
END
