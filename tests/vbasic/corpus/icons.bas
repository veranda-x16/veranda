' Icons, tiles and pictures
brush$ = PICTURE$(DATA)
DATA 8, 2, "#..##..#", ".##..##."
logo$ = PICTURE$("Logo.pic")
ICON 1, 16, 40, brush$, PickBrush
ICON 2, 48, 40, logo$, PickLogo
BITMAP 100, 60, logo$
TILE 2, 4, "Veranda Edit"
TILE 12, 4, "Paint", SKY
ICON OFF 1
ICONS CLEAR
SUB PickBrush: BEEP: END SUB
SUB PickLogo: SOUND SND_MENU: END SUB
