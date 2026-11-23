/* gate view: the scene (AUTOSTART, built with tests/view_play.c). It
   draws a picture with patterns, lines, text and paper colours in a red
   ink, writes it as SCENE.RAW (view_test_snap), exports two BMPs with
   ExportRect -- Line.bmp, 400 x 300 from x 44 (mid-card), 1 bpp, and
   Color.bmp, the whole screen, 4 bpp; Line.bmp again as "Holiday photos
   from the lake 2026.bmp", for View's Open dialog (V82) -- and starts View (its test build
   runs its sequence). */
#include <veranda.h>

void view_test_snap(const char *name);

int main(void)
{
    unsigned int i;
    unsigned char e;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(0, 0, 639, 479);
    for (i = 0; i < 12; ++i) {
        SetPattern(i + 2);
        WRectangle(20 + i * 50, 60 + i * 9, 60 + i * 50, 140 + i * 20);
        WFrameRectangle(0xFF, 18 + i * 50, 58 + i * 9, 62 + i * 50, 142 + i * 20);
    }
    for (i = 0; i < 640; i += 37)
        WDrawLine(DRAW_INK, i, 16, 639 - i, 479);
    WPutString("View: a scene for ExportRect, 1 and 4 bpp.", 32, 30);
    WPutString("Text in the system font", 300, 380);
    WInvertRectangle(400, 396, 527, 411);
    ColorRect(2, 10, 3, 6, 2);
    ColorRect(30, 12, 20, 9, 5);
    ColorRect(60, 20, 40, 20, 14);
    ColorRect(0, 80, 58, 2, 7);
    SetColors(0xFFFF, 0xF00);           /* a red ink */
    view_test_snap("SCENE.RAW");
    e = ExportRect("Line.bmp", 44, 40, 443, 339, 0);
    e |= ExportRect("Color.bmp", 0, 0, 639, 479, 0x80);
    e |= ExportRect("Holiday photos from the lake 2026.bmp", 44, 40, 443, 339, 0);  /* (a long name: V82) */
    LogText(e ? "VIEW EXPORT FAILED" : "VIEW EXPORTED");
    e = GetFile("View", 0, 0, 0, 0);
    LogText("VIEW DID NOT START");
    return 0;
}
