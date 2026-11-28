/* VeraBASIC, the editor: B_FMT's bars (textkit's view.c calls keys.c's
   tk_status and tk_title, which call these: B_VIEW's room, V215). The
   texts go to the window chrome (overlay 7's vr_win_status, vr_win_title)
   in LOW's tk_line and main RAM's scratch.

   MIT licence (LICENSE). */
#include <string.h>
#include <vrwin.h>
#include "ide.h"

static const char *const states[] = { "Ready", "Modified" };

/* the status bar (Sunroom, V149: the chrome band's texts in the UI font,
   vr_win_status): a message or the syntax of the keyword at the cursor at
   the left; the state and the cursor's line:column at the right */
void ide_status(void)
{
    char *p = tk_put_s(tk_line, stop_line ? "Stopped" : err_line ? "Error" : states[modified]);
    p = tk_put_s(p, "     ");
    p = tk_put_ul(p, cur_line + 1);
    *p++ = ':';
    *tk_put_ul(p, (unsigned long)tk_ccol + 1) = 0;
    vr_win_status(&tk_win, status_msg[0] ? status_msg : syn_line, tk_line);
}

/* the title band: the program, modified, its folder */
void ide_title(void)
{
    unsigned char l;
    char *q = tk_line;
    q = tk_put_s(q, "VeraBASIC: ");
    q = tk_put_s(q, docname[0] ? docname : "Untitled");
    if (modified)
        q = tk_put_s(q, " *");
    q = tk_put_s(q, "  -  ");
    l = strlen((char *)curDirName);
    if (l > 30) {
        q = tk_put_s(q, "...");
        q = tk_put_s(q, (char *)curDirName + l - 27);
    } else
        q = tk_put_s(q, (char *)curDirName);
    *q = 0;
    vr_win_title(&tk_win, tk_line);
}
