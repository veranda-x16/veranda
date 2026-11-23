/* gate archive: Paint opens the picture Archive converted (tests/paint_play.c,
   PAINT_ARCHIVE): File/Open (the SDK's dialog, DECISIONS V79, V82: the
   folder's .cvt files, AUTOSTART and that document), 's' selects it,
   Return opens it; the open writes OPENED.RAW and OPENED.MAP, and the end
   a VRAM dump */
P(0, 320, 240, 0),
P(10, 80, 7, 0),  /* File (the Veranda look's bar, the UI font: tests/look_menu.py) */
P(11, 80, 7, 1),
P(12, 80, 7, 0),
P(14, 80, 40, 0),  /* Open (item 1: 16 lines an item from 16) */
P(20, 80, 40, 1),
P(22, 80, 40, 0),
K(160, 's'),  /* Sunset 1 selected */
K(200, 13),  /* Return: open */
P(2400, 320, 470, 0),  /* the pointer out of the picture */
END(2460)
