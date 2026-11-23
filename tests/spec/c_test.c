/* gate spec: the C header compiles and the bindings link */
#include "veranda.h"

void main(void)
{
	unsigned char h;
	SetVideoMode(MODE_640x480);
	SetPattern(2);
	WRectangle(10, 20, 630, 470);
	WPutString("Veranda", 300, 240);
	h = FOpen("TEST", 'r');
	FClose(h);
	if (WTestPoint(10, 20))
		r0 = mouseXPos;
}
