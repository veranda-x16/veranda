' Sounds: the system's, a voice, a tune in the background (gate vb_ui)
OPTION INTEGER
WINDOW #1, 20, 10, 40, 12, "Sounds", STATUS 2
SOUND SND_OPEN
SLEEP 30
BEEP
SLEEP 30
VOICE 0, 440, 63, PULSE, 63
SLEEP 20
VOICE 0, 0, 0
PLAY 1, "T240 O4 L8 C D E F G A B > C"
WINDOW STATUS #1, "Playing", ""
SLEEP 120
SOUND OFF
VOICE 3, 1000, 40, TRIANGLE
WINDOW STATUS #1, "Voice 3 at 1000 Hz", ""
PRINT "done"
END
