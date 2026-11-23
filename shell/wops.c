/* Veranda shell: a window opened, closed, brought to the front, moved
   (CopyRect, then what it uncovered drawn again: win.c) and resized
   (overlay 7; DECISIONS V70; the menu bar's clock is the kernel's: V74). */
#include <veranda.h>
#include <string.h>
#include "shell.h"
#include "winp.h"
#pragma code-name ("OVERLAY7")

void colour_move(unsigned char x, unsigned char y, unsigned char w, unsigned char h, unsigned char nx, unsigned char ny);

/* window w opened (its path read) and in front (curDirName is its path) */
static void win_open_(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned int l = L(w), t = T(w), r = RS(w), b = BS(w);
    unsigned char was = p->open;
    p->open = 1;
    XCALL(bDir, dir_read, FB)(w | 0x80);       /* (V165: the page shown first) */
    if (was && (l != L(w) || t != T(w)))
        XCALL(bWin, win_repaint, void (*)(unsigned int, unsigned int, unsigned int, unsigned int))(l, t, r, b);
    XCALL(bWin, win_redraw, FB)(w);
    XCALL(bIc2, dir_rest, FB)(w);
    strcpy(msg, "SHELL WINDOW ");
    num(w, msg + 13);
    strcat(msg, " OPEN ");
    strcat(msg, p->path);
    LogText(msg);
}

static void win_close_(unsigned char w)
{
    struct win *p = &wins[w];
    p->open = 0;
    if (w)
        deskDirty = 1;
    found_on = 0;
    p->zw = 0;
    XCALL(bLook3, ic3_mark, FB)(w);     /* (V165: its page's icons may go) */
    shell_front(wins[w ^ 1].open ? w ^ 1 : 0xFF);
    XCALL(bWin, win_repaint, void (*)(unsigned int, unsigned int, unsigned int, unsigned int))(L(w), T(w), RS(w), BS(w));
    strcpy(msg, "SHELL WINDOW ");
    num(w, msg + 13);
    strcat(msg, " CLOSED");
    LogText(msg);
}

/* window w to the front, drawn whole */
void win_front(unsigned char w)
{
    unsigned char o = front;
    if (w == front)
        return;
    if (found_on && o < NWIN)           /* (its contents the find's results) */
        foundWin = o + 1;
    found_on = 0;
    shell_front(w);
    XCALL(bWin, win_behind, FB)(o);     /* (its title band: chrome, not bold) */
    XCALL(bWin, win_raise, FB)(w);
}

/* window w moved to card x, row y: CopyRect, then the uncovered parts */
static void win_move_(unsigned char w, unsigned char nx, unsigned int ny)
{
    struct win *p = &wins[w];
    unsigned int l = L(w), t = T(w), r = RS(w), b = BS(w), nl, nt, nr, nb, y0, y1;
    unsigned int pl[6], pt[6], pr[6], pb[6], ml, mt, mr, mb;
    unsigned char n = 0, i, j, ox = p->x;
    unsigned long c0;
    unsigned char *q = (unsigned char *)&c0;
    if (nx == p->x && ny == p->y)
        return;
    if (testing) {
        q[0] = *(volatile unsigned char *)0x9FB8;   /* (the emulator's cycle counter: the gates only, V101) */
        q[1] = *(volatile unsigned char *)0x9FB9;
        q[2] = *(volatile unsigned char *)0x9FBA;
        q[3] = *(volatile unsigned char *)0x9FBB;
    }
    p->zw = 0;
    dispBufferOn = BOTH;
    CopyRect(p->x, p->w, t, p->h, nx, ny);
    p->x = nx;
    p->y = ny;
    nl = L(w);
    nt = T(w);
    nr = RS(w);
    nb = BS(w);
    /* the new shadow's place (drawn again under it, then the shadow) */
    if (nr > R(w)) {
        pl[n] = R(w) + 1, pt[n] = nt, pr[n] = nr, pb[n] = nb;
        ++n;
    }
    if (nb > B(w)) {
        pl[n] = nl, pt[n] = B(w) + 1, pr[n] = R(w), pb[n] = nb;
        ++n;
    }
    /* the old place less the new: bands above and below, then beside */
    if (nt > t) {
        pl[n] = l, pt[n] = t, pr[n] = r, pb[n] = nt - 1 < b ? nt - 1 : b;
        ++n;
    }
    if (nb < b) {
        pl[n] = l, pt[n] = nb + 1 > t ? nb + 1 : t, pr[n] = r, pb[n] = b;
        ++n;
    }
    y0 = t > nt ? t : nt;
    y1 = b < nb ? b : nb;
    if (y0 <= y1) {
        if (nl > l) {
            pl[n] = l, pt[n] = y0, pr[n] = nl - 1 < r ? nl - 1 : r, pb[n] = y1;
            ++n;
        }
        if (nr < r) {
            pl[n] = nr + 1 > l ? nr + 1 : l, pt[n] = y0, pr[n] = r, pb[n] = y1;
            ++n;
        }
    }
    /* two parts as one while that misses the window's new place (the
       scene draws less twice: DECISIONS V81) */
    for (i = 0; i < n; ++i)
        for (j = i + 1; j < n; ++j) {
            ml = pl[i] < pl[j] ? pl[i] : pl[j];
            mt = pt[i] < pt[j] ? pt[i] : pt[j];
            mr = pr[i] > pr[j] ? pr[i] : pr[j];
            mb = pb[i] > pb[j] ? pb[i] : pb[j];
            if (ml <= R(w) && mr >= nl && mt <= B(w) && mb >= nt)
                continue;
            pl[i] = ml, pt[i] = mt, pr[i] = mr, pb[i] = mb;
            --n;
            pl[j] = pl[n], pt[j] = pt[n], pr[j] = pr[n], pb[j] = pb[n];
            j = i;
        }
    /* each part drawn in the back screen with the kernel's clip on it
       (DECISIONS V81): what lies under the window, which CopyRect drew, is
       not touched (no imprint), what does not meet the part not drawn */
    dispBufferOn = ST_WR_BACK;
    for (i = 0; i < n; ++i)
        XCALL(bWin, win_scene, void (*)(unsigned int, unsigned int, unsigned int, unsigned int, unsigned char))(pl[i], pt[i], pr[i], pb[i], w);
    dispBufferOn = BOTH;
    for (i = 0; i < n; ++i)
        WRecoverRectangle(pl[i], pt[i], pr[i], pb[i]);
    XCALL(bBars, chrome_shadow, FB)(w);
    /* the colours: the window's moved with it (CopyRect moves no colours),
       the parts' coloured again */
    if (!lookNone)
        colour_move(ox, t >> 3, p->w, p->h >> 3, nx, ny >> 3);
    for (i = 0; i < n; ++i)
        XCALL(bWin, colours_in, void (*)(unsigned int, unsigned int, unsigned int, unsigned int))(pl[i], pt[i], pr[i], pb[i]);
    if (guiOn) {                        /* its corners on what is under them now (V102) */
        XCALL(bWall, gui_ink, FBB)(w, 3);
        XCALL(bWall, gui_win, FB)(w | 0x80);   /* (the corners alone: the title band moved with it) */
    }
    if (testing) {                              /* the time the move took (V78) */
        unsigned long c;
        unsigned char *q = (unsigned char *)&c;
        q[0] = *(volatile unsigned char *)0x9FB8;
        q[1] = *(volatile unsigned char *)0x9FB9;
        q[2] = *(volatile unsigned char *)0x9FBA;
        q[3] = *(volatile unsigned char *)0x9FBB;
        strcpy(msg, "SHELL MOVED IN ");
        num(c - c0, msg + 15);
        strcat(msg, " CYCLES");
        LogText(msg);
    }
    if (w)
        deskDirty = 1;
    strcpy(msg, "SHELL WINDOW ");
    num(w, msg + 13);
    strcat(msg, " AT ");
    num(nl, msg + strlen(msg));
    strcat(msg, " ");
    num(nt, msg + strlen(msg));
    LogText(msg);
}

static void win_resize_(unsigned char w, unsigned char nw, unsigned int nh)
{
    struct win *p = &wins[w];
    unsigned int l = L(w), t = T(w), r = RS(w), b = BS(w);
    unsigned char per;
    p->w = nw;
    p->h = nh;
    p->zw = 0;
    XCALL(bWin, win_clamp, FB)(w);
    if (RS(w) > r)
        r = RS(w);
    if (BS(w) > b)
        b = BS(w);
    per = XCALL(bView, view_per, RB)(w);
    if (per && p->view != V_LIST)
        p->first -= p->first % per;
    if (w)
        deskDirty = 1;
    XCALL(bWin, win_repaint, void (*)(unsigned int, unsigned int, unsigned int, unsigned int))(l, t, r, b);
    strcpy(msg, "SHELL WINDOW ");
    num(w, msg + 13);
    strcat(msg, " SIZE ");
    num(p->w * 8, msg + strlen(msg));
    strcat(msg, " ");
    num(p->h, msg + strlen(msg));
    LogText(msg);
}


void win_open(unsigned char w)
{
    unsigned char busy = play_busy;     /* (the script waits while it draws) */
    play_busy = 1;
    win_open_(w);
    play_busy = busy;
}

void win_close(unsigned char w)
{
    unsigned char busy = play_busy;     /* (the script waits while it draws) */
    play_busy = 1;
    win_close_(w);
    play_busy = busy;
}

void win_move(unsigned char w, unsigned char nx, unsigned int ny)
{
    unsigned char busy = play_busy;     /* (the script waits while it draws) */
    play_busy = 1;
    win_move_(w, nx, ny);
    play_busy = busy;
}

void win_resize(unsigned char w, unsigned char nw, unsigned int nh)
{
    unsigned char busy = play_busy;     /* (the script waits while it draws) */
    play_busy = 1;
    win_resize_(w, nw, nh);
    play_busy = busy;
}
