' Dice: icons, sprites and sounds
APP NAME "Dice", CLASS "Dice", VERSION "1.0"
OPTION INTEGER
DIM face$(6)
FOR i = 1 TO 6: face$(i) = PICTURE$(DATA): NEXT
DATA 8, 1, "...##..."
DATA 8, 1, "##....##"
DATA 8, 1, "##.##.##"
DATA 8, 1, "##.##.##"
DATA 8, 1, "#.#.#.#."
DATA 8, 1, "########"
ICON 1, 300, 200, face$(1), Roll
SPRITE 2, face$(6): SPRITE 2 AT 100, 100: SPRITE 2 ON
WAIT EVENTS
SUB Roll
  LOCAL d
  d = INT(RND(1) * 6) + 1
  ICON OFF 1
  ICON 1, 300, 200, face$(d), Roll
  IF d = 6 THEN SOUND SND_OPEN ELSE BEEP
END SUB
