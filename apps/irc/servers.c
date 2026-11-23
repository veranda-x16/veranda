/* Veranda Chat: the servers (overlay 3; DECISIONS V111).

   CHAT.SERVERS in the system's data folder (/VERANDA/.SYSTEM, vrpath.h's
   VR_DATA), one server a line (Veranda FTP's FTP.SITES, V100, its way):

       name,host,port,nick,alternative nick,real name,password,channels

   Plain text, so it can be written on a PC too (CR LF or LF); a field
   cannot hold a comma; the channels joined at the start by spaces
   ("#retro #x16"). The password (the server's PASS, for a bouncer or a
   registered nick on servers that take it so) is kept as typed, in plain
   text. When the file is not there: Libera.Chat, SDF and EFnet, all on
   the plain port 6667 (written at the first Connect).

   The page (over the text, the input line): the servers at its top (a
   click selects, a double click connects), the selected one's fields
   under them (a click or Tab, Down, Up moves; typing edits; Backspace),
   the buttons Connect, New, Delete, Close; PgUp and PgDn select a
   server, Return connects, Esc closes. Written when it connects or
   closes, if something changed.

   The table is in this overlay's bank; what goes to the kernel (the
   file's bytes) through main RAM's line.

   Also here: the clipboard's text (Ctrl+V), a connection's end's box.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include <scrap.h>
#include <vrnet.h>
#include <vrwin.h>
#include "chat.h"
#pragma code-name ("OVERLAY3")
#pragma bss-name ("OVL3BSS")
#pragma rodata-name ("OVL3RO")

#define SV_MAX 8
#define NF     8

static struct srv sv[SV_MAX];
static unsigned char sv_n, sel, field, dirty_sv;
static unsigned char buf[64];

#pragma data-name (push, "DATA")
static char fname[] = "CHAT.SERVERS";     /* (main RAM: the kernel reads it) */
#pragma data-name (pop)

#define TOPY    48
#define LISTY   80
#define FORMY   216
#define BTNY    352
#define FX      14
#define FW      64

static const char *const defaults[3] = {
    "Libera.Chat,irc.libera.chat,6667,X16user,X16user_,Veranda Chat user,,",
    "SDF,irc.sdf.org,6667,X16user,X16user_,Veranda Chat user,,",
    "EFnet,irc.efnet.org,6667,X16user,X16user_,Veranda Chat user,,",
};

static char *__fastcall__ fptr(struct srv *s, unsigned char f)
{
    switch (f) {
    case 0: return s->name;
    case 1: return s->host;
    case 3: return s->nick;
    case 4: return s->alt;
    case 5: return s->real;
    case 6: return s->pass;
    case 7: return s->chans;
    }
    return 0;
}

static const unsigned char maxlen[NF] = { 23, 63, 5, 16, 16, 39, 31, 63 };

/* one line (line[0 .. len - 1]) into sv[sv_n] */
static void __fastcall__ parse(unsigned char len)
{
    unsigned char f = 0, i, k = 0, c;
    struct srv *s = &sv[sv_n];
    char *d;
    unsigned int v = 0;
    memset(s, 0, sizeof *s);
    line[len] = ',';
    for (i = 0; i <= len && f < NF; ++i) {
        c = line[i];
        if (c == ',' || (i == len)) {
            ++f;
            k = 0;
            continue;
        }
        if (f == 2) {
            if (c >= '0' && c <= '9')
                v = v * 10 + c - '0';
            continue;
        }
        d = fptr(s, f);
        if (k < maxlen[f])
            d[k++] = c;
    }
    s->port = v ? v : 6667;
    if (s->host[0])
        ++sv_n;
}

static unsigned char __fastcall__ fopen_sv(unsigned char mode)
{
    unsigned char h;
    vr_cd(VR_DATA);
    h = FOpen((void *)fname, mode);
    if (h < 2 || h > 4)
        h = 0;
    else if (mode == 'r' && dosStatus >= 20) {
        FClose(h);                      /* (CMDR-DOS opens a file that is not there) */
        h = 0;
    }
    return h;
}

void sv_load(void)
{
    unsigned char h = fopen_sv('r'), n = 0, i, c, k;
    sv_n = sel = field = dirty_sv = 0;
    if (h) {
        for (;;) {
            k = FRead(h, line + 128, 64);
            if (!k)
                break;
            memcpy(buf, line + 128, k);
            for (i = 0; i < k; ++i) {
                c = buf[i];
                if (c == '\r' || c == '\n') {
                    if (n && sv_n < SV_MAX)
                        parse(n);
                    n = 0;
                } else if (n < 126)
                    line[n++] = c;
            }
            if (k < 64)
                break;
        }
        if (n && sv_n < SV_MAX)
            parse(n);
        FClose(h);
    }
    if (!h) {
        for (i = 0; i < 3; ++i) {
            strcpy(line, defaults[i]);
            parse(strlen(line));
        }
        dirty_sv = 1;
    }
#ifdef CHAT_TEST
    strcpy(line, "IR SERVERS ");
    for (i = 0; i < sv_n; ++i) {
        strcat(line, sv[i].name);
        strcat(line, ";");
    }
    gt_log(line);
#endif
}

static void __fastcall__ wr(unsigned char h, const char *s)
{
    if (FWrite(h, (void *)s, strlen(s)))
        sv_err = 1;
}

static void save(void)
{
    unsigned char h, i, f;
    struct srv *s;
    dirty_sv = 0;
    sv_err = 0;
    h = fopen_sv('w');
    if (!h) {
        sv_err = 1;
        message("CHAT.SERVERS cannot be written.", "(the servers are in /VERANDA/.SYSTEM)");
        return;
    }
    for (i = 0; i < sv_n; ++i) {
        s = &sv[i];
        for (f = 0; f < NF; ++f) {
            if (f == 2)
                unum(line + 100, s->port);
            else
                strcpy(line + 100, fptr(s, f));
            strcat(line + 100, f == NF - 1 ? "\r\n" : ",");
            wr(h, line + 100);
        }
    }
    FClose(h);
}

/*---------------------------------------------------------------- the page */

static const char *const labels[NF] = { "Name", "Host", "Port", "Nick", "Alt. nick", "Real name", "Password", "Channels" };

static void __fastcall__ sv_row(unsigned char i)
{
    unsigned int y = LISTY + i * 16;
    unsigned char on = i == sel && i < sv_n, hl = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    struct srv *s = &sv[i];
    char *p;
    theme_rect(1, 78, y >> 3, 2, on && hl ? hl : 0);
    line[0] = 0;
    if (i < sv_n) {
        memset(line, ' ', 76);
        memcpy(line, s->name, strlen(s->name));
        p = line + 26;
        strcpy(p, s->host);
        strcat(p, ":");
        unum(p + strlen(p), s->port);
        p[strlen(p)] = ' ';
        memcpy(line + 56, s->nick, strlen(s->nick));
        line[76] = 0;
    } else if (i == 0)
        strcpy(line, "No servers: New adds one.");
    put(2, y + 4, line, 76, on && !hl);
}

static void __fastcall__ field_row(unsigned char f)
{
    unsigned int y = FORMY + f * 16;
    unsigned char n, i;
    char *v;
    put(2, y + 4, labels[f], 11, 0);
    line[0] = 0;
    if (sel < sv_n) {
        v = fptr(&sv[sel], f);
        if (f == 2)
            unum(line, sv[sel].port);
        else if (f == 6) {
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
    theme_rect(FX, FW, y >> 3, 2, sel < sv_n ? (f == field ? CHROME : SIDEBAR) : 0);
}

/* (V149) text in the UI font at x, its top at y (bold: a heading);
   through line (main RAM: the kernel reads it); its width (y 480: only
   measured) */
static unsigned int __fastcall__ uitext(unsigned int x, unsigned int y, const char *t, unsigned char bold)
{
    unsigned int w = 0;
    const char *p;
    UseFont(FONT_UI);
    currentMode = bold ? SET_BOLD : 0;
    strcpy(line, t);
    for (p = line; *p; ++p)
        w += GetCharWidth(*p) + bold;
    if (y < 480)
        WPutString(line, x, y + baselineOffset);
    currentMode = 0;
    UseSystemFont();
    return w;
}

/* a rounded frame (radius 2) */
static void __fastcall__ rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    WHorizontalLine(0xFF, l + 2, r - 2, t);
    WHorizontalLine(0xFF, l + 2, r - 2, b);
    WVerticalLine(0xFF, l, t + 2, b - 2);
    WVerticalLine(0xFF, r, t + 2, b - 2);
    WHorizontalLine(0xFF, l + 1, l + 1, t + 1);
    WHorizontalLine(0xFF, r - 1, r - 1, t + 1);
    WHorizontalLine(0xFF, l + 1, l + 1, b - 1);
    WHorizontalLine(0xFF, r - 1, r - 1, b - 1);
}

/* the buttons (V149, Sunroom: framed, their labels centred in the UI font,
   bold; Connect, Return's, the default: a frame two pixels thick) */
#define BW 10
static const unsigned char bx[4] = { 2, 13, 24, 35 };
static const char *const bname[4] = { "Connect", "New", "Delete", "Close" };

static void draw(void)
{
    unsigned char i;
    unsigned int l, w;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, TOPY, 639, 463);
    theme_rect(0, 80, TOPY >> 3, 58 - (TOPY >> 3), 0);
    w = uitext(16, TOPY + 2, "Servers", 1);
    uitext(24 + w, TOPY + 2, "choose one and Connect (CHAT.SERVERS)", 0);
    uitext(16, LISTY - 15, "Name", 1);
    uitext(224, LISTY - 15, "Host:port", 1);
    uitext(464, LISTY - 15, "Nick", 1);
    WHorizontalLine(0xFF, 8, 631, LISTY - 2);
    for (i = 0; i < SV_MAX; ++i)
        sv_row(i);
    WHorizontalLine(0xFF, 8, 631, FORMY - 6);
    for (i = 0; i < NF; ++i)
        field_row(i);
    for (i = 0; i < 4; ++i) {
        l = bx[i] * 8;
        theme_rect(bx[i], BW, BTNY >> 3, 2, CHROME);
        rframe(l, BTNY, l + BW * 8 - 1, BTNY + 15);
        if (!i)
            rframe(l + 1, BTNY + 1, l + BW * 8 - 2, BTNY + 14);
        w = uitext(0, 480, bname[i], 1);
        uitext(l + ((BW * 8 - w) >> 1), BTNY + 2, bname[i], 1);
    }
    put(2, 392, "Tab, Down, Up: a field; PgUp, PgDn: a server; Return: connect; Esc: close.", 78, 0);
    put(2, 408, "Channels: joined when connected, by spaces (#retro #x16). The password is", 78, 0);
    put(2, 420, "the server's (PASS), kept as plain text in /VERANDA/.SYSTEM/CHAT.SERVERS.", 78, 0);
    put(2, 436, "The port is a plain one (6667): there is no TLS on the X16.", 78, 0);
}

void sv_show(void)
{
    if (sel >= sv_n)
        sel = 0;
    field = 3;
    sv_page = 1;
    draw();
#ifdef CHAT_TEST
    gt_log("IR SERVERS SHOWN");
#endif
}

static void close_page(void)
{
    if (dirty_sv)
        save();
    sv_page = 0;
}

static void go(void)
{
    if (sel >= sv_n || !sv[sel].host[0]) {
        Beep();
        return;
    }
    if (!sv[sel].nick[0])
        strcpy(sv[sel].nick, "X16user");
    memcpy(&S, &sv[sel], sizeof S);
    close_page();
    sv_go = 1;
}

static void new_sv(void)
{
    struct srv *s;
    if (sv_n >= SV_MAX) {
        Beep();
        return;
    }
    s = &sv[sv_n];
    memset(s, 0, sizeof *s);
    s->port = 6667;
    sel = sv_n++;
    field = 0;
    dirty_sv = 1;
    draw();
}

static void del_sv(void)
{
    if (sel >= sv_n)
        return;
    strcpy(line, "Forget the server ");
    strncat(line, sv[sel].name, 24);
    if (!yesno(line, "?"))
        return;
    memmove(&sv[sel], &sv[sel + 1], (sv_n - sel - 1) * sizeof(struct srv));
    --sv_n;
    if (sel && sel >= sv_n)
        --sel;
    dirty_sv = 1;
    draw();
}

static void __fastcall__ select(unsigned char i)
{
    unsigned char o = sel, f;
    if (i >= sv_n || i == sel)
        return;
    sel = i;
    sv_row(o);
    sv_row(i);
    for (f = 0; f < NF; ++f)
        field_row(f);
}

static void __fastcall__ focus(unsigned char f)
{
    unsigned char o = field;
    field = f;
    field_row(o);
    field_row(f);
}

void sv_key(void)
{
    unsigned char k = keyData, n;
    char *v;
    switch (k) {
    case KEY_ESC: close_page(); return;
    case 13: go(); return;
    case KEY_TAB: focus(field == NF - 1 ? 0 : field + 1); return;
    case KEY_PGUP: if (sel) select(sel - 1); return;
    case KEY_PGDN: select(sel + 1); return;
    }
    if (keyDataMods & KEYM_ARROW) {
        if (k == KEY_DOWN)
            focus(field == NF - 1 ? 0 : field + 1);
        else if (k == KEY_UP)
            focus(field ? field - 1 : NF - 1);
        return;
    }
    if (sel >= sv_n)
        return;
    v = fptr(&sv[sel], field);
    if (k == 8) {                       /* Backspace */
        if (field == 2)
            sv[sel].port /= 10;
        else if ((n = strlen(v)) != 0)
            v[n - 1] = 0;
    } else if (k >= 32 && k < 127 && k != ',') {
        if (field == 2) {
            if (k < '0' || k > '9' || sv[sel].port >= 6553)
                return;
            sv[sel].port = sv[sel].port * 10 + k - '0';
        } else {
            n = strlen(v);
            if (n >= maxlen[field])
                return;
            v[n] = k;
            v[n + 1] = 0;
        }
    } else
        return;
    dirty_sv = 1;
    field_row(field);
    if (field < 4)
        sv_row(sel);
}

void sv_press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    unsigned char i, c = x >> 3;
    if (y >= LISTY && y < LISTY + SV_MAX * 16) {
        i = (y - LISTY) >> 4;
        if (i < sv_n && i == sel && dblClickCount) {
            dblClickCount = 0;
            go();
            return;
        }
        dblClickCount = CLICK_COUNT;
        select(i);
        return;
    }
    if (y >= FORMY && y < FORMY + NF * 16) {
        focus((y - FORMY) >> 4);
        return;
    }
    if (y >= BTNY && y < BTNY + 16) {
        for (i = 0; i < 4; ++i)
            if (c >= bx[i] && c < bx[i] + BW)
                break;
        switch (i) {
        case 0: go(); break;
        case 1: new_sv(); break;
        case 2: del_sv(); break;
        case 3: close_page(); break;
        }
    }
}

void sv_paste(void)
{
    if (!scrap_get_text(line, sizeof line))
        line[0] = 0;
}

/*---------------------------------------------------------------- a connection's end: its box */

static const char *net_why(void)
{
    switch (cnet) {
    case NET_ERR: return "(refused, or no such host)";
    case NET_ETIMEOUT: return "(no answer)";
    case NET_EBADARG: return "(a bad host name)";
    case NET_ENOSOCK: return "(no free connection)";
    case NET_EBADCRC: return "(data from the modem was lost: a bad checksum)";   /* (V179) */
    case NET_EIO: return "(the modem's reply made no sense)";
    case NET_ECLOSED: return "(the modem says the connection closed)";
    }
    return "(the modem's connection failed)";
}

void sv_box(void)
{
    switch (cbox) {
    case CE_NET:
        strcpy(line, cbox_st >= C_REG ? "The connection to " : "Could not connect to ");
        strncat(line, S.host, 30);
        if (cbox_st >= C_REG)
            strcat(line, " failed");
        message(line, net_why());
        break;
    case CE_CLOSED:
        strcpy(line, "The server ");
        strncat(line, S.name[0] ? S.name : S.host, 24);
        strcat(line, " closed the connection.");
        message(line, cwhy[0] ? cwhy : "(no reason given)");
        break;
    case CE_TIMEOUT:
        message("The server stopped answering.", "(nothing for 5 minutes: the connection was closed)");
        break;
    case CE_MODEM:
        message("The modem does not answer.", "(TexElec's Serial & ESP32 Network Card)");
        break;
    case CE_NOCARD:
        message("No network card was found.", "(TexElec's Serial & ESP32 Network Card)");
        break;
    }
}
