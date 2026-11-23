/* Veranda FTP: the saved servers (overlay 2; DECISIONS V100).

   FTP.SITES in the system's data folder (/VERANDA/.SYSTEM, vrpath.h's
   VR_DATA), one server a line (Packet16's PACKET16.SIT, Marcin
   Spoczynski's sites.c, with a sixth field, the start folder):

       name,host,port,user,password,folder

   Plain text, so it can be written on a PC too; a field cannot hold a
   comma. The password is kept as it is typed, in plain text, as
   Packet16 keeps it (the README says so). An empty user logs in as
   "anonymous".

   The page (in the body of the window, over the panes): the servers at
   its top (a click selects, a double click connects), the selected one's
   fields under them (a click or Tab, Down, Up moves between them; typing
   edits the one marked; Backspace), the buttons Connect, New, Delete,
   Close; PgUp and PgDn select a server, Return connects, Esc closes.
   Changes are written when the page closes or connects.

   The table is in this overlay's bank; what goes to the kernel (the
   file's bytes, the texts) through main RAM's buffers.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include "ftp.h"
#pragma code-name ("OVERLAY2")
#pragma bss-name ("OVL2BSS")

#define SITE_MAX 8

static struct site sites[SITE_MAX];
static unsigned char sel, field, dirty;

static const char fname[] = "FTP.SITES";

#define SLISTY   80
#define FORMY   232
#define BTNY    344
#define FX      14              /* the fields' column */
#define FW      50

static void __fastcall__ copy(char *d, const char *s, unsigned char n, unsigned char max)
{
    if (n >= max)
        n = max - 1;
    memcpy(d, s, n);
    d[n] = 0;
}

/* one line (in line[]) into sites[sites_n] */
static void __fastcall__ parse(unsigned char len)
{
    unsigned char start[7], f = 0, i;
    struct site *s = &sites[sites_n];
    unsigned int v = 0;
    start[0] = 0;
    for (i = 0; i < len && f < 6; ++i)
        if (line[i] == ',')
            start[++f] = i + 1;
    if (f < 4)
        return;
    while (f < 6)
        start[++f] = len + 1;           /* (no folder: empty) */
    start[6] = len + 1;
    memset(s, 0, sizeof *s);
    copy(s->name, line + start[0], start[1] - 1 - start[0], sizeof s->name);
    copy(s->host, line + start[1], start[2] - 1 - start[1], sizeof s->host);
    for (i = start[2]; i < start[3] - 1 && line[i] >= '0' && line[i] <= '9'; ++i)
        v = v * 10 + line[i] - '0';
    s->port = v ? v : 21;
    copy(s->user, line + start[3], start[4] - 1 - start[3], sizeof s->user);
    if (start[5] <= len) {
        copy(s->pass, line + start[4], start[5] - 1 - start[4], sizeof s->pass);
        copy(s->dir, line + start[5], len - start[5], sizeof s->dir);
    } else
        copy(s->pass, line + start[4], len - start[4], sizeof s->pass);
    if (s->host[0])
        ++sites_n;
}

static unsigned char __fastcall__ fopen_sites(unsigned char mode)
{
    unsigned char h;
    vr_cd(VR_DATA);
    h = FOpen((void *)fname, mode);
    if (h < 2 || h > 4)
        h = 0;
    else if (mode == 'r' && dosStatus >= 20) {
        FClose(h);                      /* (CMDR-DOS opens a file that is not there: Packet16's D22) */
        h = 0;
    }
    return h;
}

void sites_load(void)
{
    static unsigned char buf[64];       /* (OVL2BSS: the file's bytes come to line) */
    unsigned char h = fopen_sites('r'), ln = 0, i, c;
    unsigned int n;
    sites_n = sel = field = dirty = 0;
    if (h) {
        for (;;) {
            n = FRead(h, line + 64, 64);
            if (!n)
                break;
            memcpy(buf, line + 64, n);
            for (i = 0; i < n; ++i) {
                c = buf[i];
                if (c == '\r' || c == '\n') {
                    if (ln && sites_n < SITE_MAX)
                        parse(ln);
                    ln = 0;
                } else if (ln < 63)
                    line[ln++] = c;
            }
            if (n < 64)
                break;
        }
        if (ln && sites_n < SITE_MAX)
            parse(ln);
        FClose(h);
    }
    ChDir((char *)curDirName);
}

static void save(void)
{
    unsigned char h, i;
    char *p;
    struct site *s;
    dirty = 0;
    h = fopen_sites('w');
    if (!h) {
        ChDir((char *)curDirName);
        message("FTP.SITES cannot be written.", "");
        return;
    }
    for (i = 0; i < sites_n; ++i) {
        s = &sites[i];
        strcpy(line, s->name);
        strcat(line, ",");
        strcat(line, s->host);
        strcat(line, ",");
        p = unum(line + strlen(line), s->port);
        *p++ = ',';
        strcpy(p, s->user);
        strcat(line, ",");
        FWrite(h, line, strlen(line));
        strcpy(line, s->pass);
        strcat(line, ",");
        strcat(line, s->dir);
        strcat(line, "\r\n");
        FWrite(h, line, strlen(line));
    }
    FClose(h);
    ChDir((char *)curDirName);
}

void sites_pick(void)
{
    if (sel < sites_n)
        memcpy(&cur, &sites[sel], sizeof cur);
}

/*---------------------------------------------------------------- the page */

static const char *const labels[6] = { "Name", "Host", "Port", "User", "Password", "Folder" };
static const unsigned char maxlen[6] = { 23, 63, 5, 31, 31, 63 };

static char *__fastcall__ fptr(unsigned char f)
{
    struct site *s = &sites[sel];
    switch (f) {
    case 0: return s->name;
    case 1: return s->host;
    case 3: return s->user;
    case 4: return s->pass;
    case 5: return s->dir;
    }
    return 0;
}

static void __fastcall__ site_row(unsigned char i)
{
    unsigned int y = SLISTY + i * 16;
    unsigned char on = i == sel && i < sites_n, hl = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    struct site *s = &sites[i];
    char *p;
    theme_rect(1, 78, y >> 3, 2, on && hl ? hl : 0);
    line[0] = 0;
    if (i < sites_n) {
        memset(line, ' ', 76);
        memcpy(line, s->name, strlen(s->name));
        p = line + 26;
        strcpy(p, s->host);
        strcat(p, ":");
        unum(p + strlen(p), s->port);
        p[strlen(p)] = ' ';
        memcpy(line + 56, s->user[0] ? s->user : "anonymous", strlen(s->user[0] ? s->user : "anonymous"));
        line[76] = 0;
    } else if (i == 0)
        strcpy(line, "No saved servers yet: New adds one.");
    put(2, y + 4, line, 76, on && !hl);
}

static void __fastcall__ field_row(unsigned char f)
{
    unsigned int y = FORMY + f * 16;
    unsigned char n, i;
    char *v = fptr(f);
    line[0] = 0;
    if (sel < sites_n) {
        if (f == 2)
            unum(line, sites[sel].port);
        else if (f == 4) {
            n = strlen(v);
            for (i = 0; i < n; ++i)
                line[i] = '*';
            line[n] = 0;
        } else
            strcpy(line, v);
        if (f == field)
            strcat(line, "_");
    }
    put(FX, y + 4, line, FW, 0);
    theme_rect(FX, FW, y >> 3, 2, sel < sites_n ? (f == field ? CHROME : SIDEBAR) : 0);
}

/* (V149) the buttons: 10 cards each, framed, their names centred in the
   UI font, in the chrome's colour; Connect (Return) the default */
#define BW 10
static const unsigned char bx[4] = { 2, 13, 24, 35 };
static const char *const bname[4] = { "Connect", "New", "Delete", "Close" };

/* s in the UI font at x, its top at y (through line, below $A000); its
   width */
static unsigned int __fastcall__ label(unsigned int x, unsigned int y, const char *s, unsigned char bold)
{
    unsigned int w = 0;
    unsigned char i;
    strcpy(line, s);
    UseFont(FONT_UI);
    for (i = 0; line[i]; ++i)
        w += GetCharWidth(line[i]) + bold;
    if (x >= 640)                       /* (x - 640: the middle) */
        x -= 640 + (w >> 1);
    currentMode = bold ? SET_BOLD : 0;
    WPutString(line, x, y + baselineOffset);
    currentMode = 0;
    UseSystemFont();
    return w;
}

static void draw(void)
{
    unsigned char i;
    unsigned int x;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(0, 32, 639, 46);
    WRectangle(0, 48, 639, 463);
    theme_rect(0, 80, 4, 2, CHROME);
    theme_rect(0, 80, 6, 52, 0);
    label(8, 34, "Sites: the saved servers (FTP.SITES)", 1);
    label(16, 60, "Name", 1);
    label(16 + 26 * 8, 60, "Host:port", 1);
    label(16 + 56 * 8, 60, "User", 1);
    WHorizontalLine(0xFF, 8, 631, 75);
    for (i = 0; i < SITE_MAX; ++i)
        site_row(i);
    WHorizontalLine(0xFF, 8, 631, FORMY - 8);
    for (i = 0; i < 6; ++i) {
        label(16, FORMY + i * 16 + 2, labels[i], 0);
        field_row(i);
    }
    for (i = 0; i < 4; ++i) {
        x = bx[i] << 3;
        theme_rect(bx[i], BW, BTNY >> 3, 2, CHROME);
        WFrameRectangle(0xFF, x, BTNY, x + BW * 8 - 1, BTNY + 15);
        if (!i)                         /* (the default: two pixels, V146) */
            WFrameRectangle(0xFF, x + 1, BTNY + 1, x + BW * 8 - 2, BTNY + 14);
        label(640 + x + BW * 4, BTNY + 2, bname[i], i == 0);
    }
    label(16, 384, "Tab, Down, Up: a field; PgUp, PgDn: a server; Return: connect; Esc: close.", 0);
    label(16, 400, "An empty user logs in as anonymous. The password is kept as plain text in FTP.SITES,", 0);
    label(16, 416, "in the system's folder (/VERANDA/.SYSTEM).", 0);
}

void sites_show(void)
{
    if (sel >= sites_n)
        sel = 0;
    field = 1;
    draw();
#ifdef FTP_TEST
    LogText("FTP SITES SHOWN");
#endif
}

static void close_page(void)
{
    if (dirty)
        save();
    page = 0;
}

static void go(void)
{
    if (sel >= sites_n || !sites[sel].host[0]) {
        Beep();
        return;
    }
    sites_pick();
    close_page();
    sites_go = 1;
}

static void new_site(void)
{
    struct site *s;
    if (sites_n >= SITE_MAX) {
        Beep();
        return;
    }
    s = &sites[sites_n];
    memset(s, 0, sizeof *s);
    strcpy(s->name, "New server");
    s->port = 21;
    sel = sites_n++;
    field = 1;
    dirty = 1;
    draw();
}

static void del_site(void)
{
    if (sel >= sites_n)
        return;
    strcpy(line, "Forget the server ");
    strncat(line, sites[sel].name, 24);
    if (!yesno(line, "?"))
        return;
    memmove(&sites[sel], &sites[sel + 1], (sites_n - sel - 1) * sizeof(struct site));
    --sites_n;
    if (sel && sel >= sites_n)
        --sel;
    dirty = 1;
    draw();
}

static void __fastcall__ select(unsigned char i)
{
    unsigned char o = sel, f;
    if (i >= sites_n || i == sel)
        return;
    sel = i;
    site_row(o);
    site_row(i);
    for (f = 0; f < 6; ++f)
        field_row(f);
}

static void __fastcall__ focus(unsigned char f)
{
    unsigned char o = field;
    field = f;
    field_row(o);
    field_row(f);
}

void sites_key(void)
{
    unsigned char k = keyData, n;
    char *v;
    switch (k) {
    case KEY_ESC: close_page(); return;
    case 13: go(); return;
    case KEY_TAB:
    case KEY_DOWN: focus(field == 5 ? 0 : field + 1); return;
    case KEY_UP: focus(field ? field - 1 : 5); return;
    case KEY_PGUP: if (sel) select(sel - 1); return;
    case KEY_PGDN: select(sel + 1); return;
    }
    if (sel >= sites_n)
        return;
    v = fptr(field);
    if (k == 8 && !(keyDataMods & KEYM_ARROW)) {        /* Backspace */
        if (field == 2)
            sites[sel].port /= 10;
        else if ((n = strlen(v)) != 0)
            v[n - 1] = 0;
    } else if (k >= 32 && k < 127 && k != ',') {
        if (field == 2) {
            if (k < '0' || k > '9' || sites[sel].port >= 6553)
                return;
            sites[sel].port = sites[sel].port * 10 + k - '0';
        } else {
            n = strlen(v);
            if (n >= maxlen[field])
                return;
            v[n] = k;
            v[n + 1] = 0;
        }
    } else
        return;
    dirty = 1;
    field_row(field);
    if (field != 4 && field != 5)
        site_row(sel);
}

void sites_press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    unsigned char i, c = x >> 3;
    if (y >= SLISTY && y < SLISTY + SITE_MAX * 16) {
        i = (y - SLISTY) >> 4;
        if (i < sites_n && i == sel && dblClickCount) {
            dblClickCount = 0;
            go();
            return;
        }
        dblClickCount = CLICK_COUNT;
        select(i);
        return;
    }
    if (y >= FORMY && y < FORMY + 6 * 16) {
        focus((y - FORMY) >> 4);
        return;
    }
    if (y >= BTNY && y < BTNY + 16) {
        for (i = 0; i < 4; ++i)
            if (c >= bx[i] && c < bx[i] + BW)
                break;
        switch (i) {
        case 0: go(); break;
        case 1: new_site(); break;
        case 2: del_site(); break;
        case 3: close_page(); break;
        }
    }
}
