/* gate canvas: the session, written by tests/canvas_script.py */
/* shot menu 230 */
/* shot closed 420 */
/* shot dialog 600 */
P(0, 160, 120, 0),
P(100, 92, 6, 0),  /* File: the menu opens (the shot) */
P(102, 92, 6, 1),
P(110, 92, 6, 0),
P(300, 100, 22, 0),  /* Close: the menu closes */
P(302, 100, 22, 1),
P(310, 100, 22, 0),
K(620, 27),  /* Esc: the Open box (CanvApp opened it at frame 480) ends */
END(60000)
