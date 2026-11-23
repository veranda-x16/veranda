' Text and fonts
FONT "Roma", 12
STYLE BOLD + ITALIC
TEXT 20, 30, "Hello"
STYLE 0
FONT UI
t$ = "Centred"
x% = 320 - TEXTWIDTH(t$) \ 2
y% = 100 + FONTHEIGHT
TEXT x%, y%, t$
FONT SYSTEM
CARDS 0, 2, "Score: " + STR$(10), BOLD
CARDS 0, 3, " Menu ", REVERSE
