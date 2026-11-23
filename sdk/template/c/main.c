/* A Veranda application in C: a title, a box, a menu with "quit".
   main() sets things up and returns; the kernel's main loop runs the rest. */
#include <veranda.h>

static void quit(void)
{
    ToBASIC(0);
}

/* a menu table as GEOS reads it (cc65 structs have no padding) */
struct menu1 {
    unsigned char top, bottom;
    unsigned int left, right;
    unsigned char flags;
    const char *text;
    unsigned char type;
    void (*action)(void);
};

static const struct menu1 menu = {
    0, 14, 0, 40, HORIZONTAL | UN_CONSTRAINED | 1,
    "quit", MENU_ACTION, quit
};

int main(void)
{
    SetPattern(2);
    WRectangle(0, 16, 639, 479);
    SetPattern(0);
    WRectangle(200, 180, 440, 300);
    WFrameRectangle(0xFF, 200, 180, 440, 300);
    WPutString("Hello from C on Veranda", 240, 244);
    DoMenu((void *)&menu, 0);
    LogText("TEMPLATE C RUNNING");
    return 0;
}
