/* Veranda Term: the Hosts page (Connection > Connect..., DECISIONS V112),
   in overlay 3 (overlay 2, with tcp.c, has no room): hosts to connect to
   over TCP, Telnet or raw, in TERM.HOSTS (/VERANDA/.SYSTEM, as FTP.SITES and GOPHER.MARKS): a line
   "name|host:port|telnet" (or "|raw"), CR LF or LF; missing, the
   defaults below. Rules as ui.c's: what goes to the kernel is copied
   below $A000 by term.c (message, ask, row_text); nothing here calls a
   resident function that maps another bank.

   MIT licence (see LICENSE). */
#pragma code-name ("OVERLAY3")
#pragma rodata-name ("OVL3RO")
#pragma data-name ("OVL3DATA")
#pragma bss-name ("OVL3BSS")
#include <string.h>
#include "term.h"
#include "net.h"

#define HOSTS 11
struct host { char name[25]; char addr[41]; unsigned char raw; };
static struct host hl[HOSTS];
static unsigned char nh, sel;
static unsigned char fresh = 1;         /* (DATA: an overlay's BSS is not cleared) */

/* long-lived Telnet BBSes and services, from memory: not checked (the
   user's own list replaces them once written) */
static const char *const defs[] = {
    "Vertrauen (Synchronet)|vert.synchro.net:23|telnet",
    "Level 29|bbs.fozztexx.com:23|telnet",
    "Black Flag|blackflag.acid.org:23|telnet",
    "Telehack|telehack.com:23|telnet",
    "NIST daytime (raw)|time.nist.gov:13|raw",
};

static char b[COLS + 1];
static char e_name[25], e_host[41], e_port[6], e_mode[2];

/* a line into hl[nh] ("name|host:port|mode"); 1 taken */
static unsigned char parse(const char *s)
{
    struct host *h = &hl[nh];
    unsigned char f = 0, i = 0, c;
    memset(h, 0, sizeof *h);
    for (; (c = *s) != 0; ++s) {
        if (c == '|') {
            ++f;
            i = 0;
        } else if (f == 0 && i < 24)
            h->name[i++] = c;
        else if (f == 1 && i < 40)
            h->addr[i++] = c;
        else if (f == 2 && i == 0) {
            h->raw = (c | 0x20) == 'r';
            ++i;
        }
    }
    if (!h->addr[0] || !strchr(h->addr, ':'))
        return 0;
    if (!h->name[0])
        strcpy(h->name, h->addr);
    ++nh;
    return 1;
}

static void load(void)
{
    unsigned char fh, i = 0, c;
    unsigned int len, k;
    nh = sel = 0;
    fh = fopen_sys("TERM.HOSTS", 'r');
    if (fh >= 2 && fh <= 9) {
        while ((len = FRead(fh, rxbuf, sizeof rxbuf)) != 0)
            for (k = 0; k < len; ++k) {
                c = rxbuf[k];
                if (c == '\n' || c == '\r') {
                    b[i] = 0;
                    if (i && nh < HOSTS)
                        parse(b);
                    i = 0;
                } else if (i < COLS)
                    b[i++] = c;
            }
        FClose(fh);
        b[i] = 0;
        if (i && nh < HOSTS)
            parse(b);
        LogText("TERM HOSTS READ");
        return;
    }
    for (i = 0; i < sizeof defs / sizeof defs[0]; ++i)
        parse(defs[i]);
}

static void save(void)
{
    unsigned char fh, i;
    char *p;
    fh = fopen_sys("TERM.HOSTS", 'w');
    if (fh < 2 || fh > 9) {
        message("Cannot write", "TERM.HOSTS");
        return;
    }
    for (i = 0; i < nh; ++i) {
        p = put_str(put_str((char *)rxbuf, hl[i].name), "|");
        p = put_str(put_str(p, hl[i].addr), hl[i].raw ? "|raw\r\n" : "|telnet\r\n");
        FWrite(fh, rxbuf, p - (char *)rxbuf);   /* (below $A000) */
    }
    FClose(fh);
    LogText("TERM HOSTS WRITTEN");
}

static const char bk[5] = { 13, 'C', 'N', 'X', 27 };   /* (the buttons' keys) */

/* row i of the list (its number, the name, host:port, the mode) */
static void host_row(unsigned char i)
{
    memset(b, ' ', COLS);
    b[COLS] = 0;
    if (i < nh) {
        b[0] = i < 9 ? '1' + i : 'A' + i - 9;
        memcpy(b + 3, hl[i].name, strlen(hl[i].name));
        memcpy(b + 30, hl[i].addr, strlen(hl[i].addr));
        memcpy(b + 70, hl[i].raw ? "raw" : "Telnet", hl[i].raw ? 3 : 6);
    }
    list_row(LISTTOP + 16 * i, b, i == sel && i < nh);
}

void o_hosts_draw(void)
{
    unsigned char i;
    if (fresh) {
        fresh = 0;
        e_name[0] = e_host[0] = e_port[0] = e_mode[0] = 0;
        e_mode[1] = 0;
        load();
    }
    page_head("Connect to a host (TCP through the Wi-Fi modem)",
              "Click, 1-9, A, B or Up, Down choose; a double click or Return connects; C another host; N new; X removes.");
    ui_text("Name", 8 + 3 * 8, TY + 48, 1);
    ui_text("Host and port", 8 + 30 * 8, TY + 48, 1);
    ui_text("Mode", 8 + 70 * 8, TY + 48, 1);
    for (i = 0; i < HOSTS; ++i)
        host_row(i);
    WHorizontalLine(0xFF, 8, 631, LISTTOP + 16 * HOSTS + 7);
    ui_text("Telnet: Term answers the options (NAWS 80 x 55, TERMINAL-TYPE ANSI, ECHO, SGA, BINARY).", 8, LISTTOP + 16 * HOSTS + 14, 0);
    ui_text("Raw: the bytes as they are. The list is TERM.HOSTS in /VERANDA/.SYSTEM; its first entries are", 8, LISTTOP + 16 * HOSTS + 30, 0);
    ui_text("well known hosts, not checked from here. The serial terminal (Dial..., AT commands) is as before.", 8, LISTTOP + 16 * HOSTS + 46, 0);
}

/* a box asking for v (max characters, v the default): edited in crow
   (resident: the box's string is not to be in an overlay's bank; crow is
   free while this page shows); 0 cancelled */
static unsigned char ask_in(const char *prompt, char *v, unsigned char max)
{
    strcpy((char *)crow, v);
    if (!ask(prompt, (char *)crow, max))
        return 0;
    strcpy(v, (char *)crow);
    return 1;
}

/* host:port and a mode asked into e_*; 1 given (host: letters, digits,
   '.' and '-'; port 1-65535) */
static unsigned char ask_host(void)
{
    unsigned char i, c;
    unsigned long v = 0;
    if (!ask_in("Host (a name or an address):", e_host, 34) || !e_host[0])
        return 0;
    for (i = 0; (c = e_host[i]) != 0; ++i)
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-')) {
            message("Not a host name:", e_host);
            return 0;
        }
    if (!e_port[0])
        strcpy(e_port, "23");
    if (!ask_in("Port (Telnet: 23):", e_port, 5))
        return 0;
    for (i = 0; (c = e_port[i]) != 0 && c >= '0' && c <= '9'; ++i)
        v = v * 10 + c - '0';
    if (c || !v || v > 65535u) {
        message("Not a port:", e_port);
        return 0;
    }
    if (!e_mode[0])
        e_mode[0] = 'T';
    if (!ask_in("T Telnet, R raw TCP:", e_mode, 1))
        return 0;
    return 1;
}

static void to_target(const char *addr, unsigned char raw)
{
    strcpy(target, addr);
    tcp_raw = raw;
}

unsigned char o_hosts_key(unsigned char k)
{
    struct host *h;
    char *p;
    if (k >= 'a' && k <= 'z')
        k -= 32;
    if (k >= '1' && k <= '9' && k - '1' < nh)
        sel = k - '1';
    else if (k >= 'A' && k <= 'B' && k - 'A' + 9 < nh)
        sel = k - 'A' + 9;
    else if (k == KEY_UP && sel)
        --sel;
    else if (k == KEY_DOWN && sel + 1 < nh)
        ++sel;
    else if (k == 13) {
        if (sel >= nh)
            return 0;
        to_target(hl[sel].addr, hl[sel].raw);
        strcpy(msga, hl[sel].name);     /* (the window's title) */
        return 2;
    } else if (k == 27)
        return 1;
    else if (k == 'C' || k == 'N') {
        if (k == 'N' && nh == HOSTS) {
            message("The list is full:", "X removes one.");
            return 0;
        }
        if (k == 'N' && !ask_in("Name:", e_name, 24))
            return 0;
        if (!ask_host())
            return 0;
        p = put_str(put_str(b, e_host), ":");
        *put_str(p, e_port) = 0;
        if (k == 'C') {
            to_target(b, (e_mode[0] | 0x20) == 'r');
            strcpy(msga, b);
            return 2;
        }
        h = &hl[nh];
        strcpy(h->name, e_name[0] ? e_name : b);
        strcpy(h->addr, b);
        h->raw = (e_mode[0] | 0x20) == 'r';
        sel = nh++;
        save();
    } else if (k == 'X') {
        if (sel >= nh)
            return 0;
        memmove(&hl[sel], &hl[sel + 1], (nh - sel - 1) * sizeof hl[0]);
        if (--nh && sel == nh)
            --sel;
        save();
    } else
        return 0;
    o_hosts_draw();
    return 0;
}

/* (V195) a click on the page: a row selects it (only the two rows drawn
   again), the selected one again within CLICK_COUNT frames (a double
   click) connects as Return; a button is its key */
unsigned char o_hosts_click(void)
{
    unsigned char i = btn_at(), old = sel;
    if (i < 5)
        return o_hosts_key(bk[i]);
    i = row_at(HOSTS);
    if (i >= nh)
        return 0;
    if (i == sel && dblClickCount) {
        dblClickCount = 0;
        return o_hosts_key(13);
    }
    dblClickCount = CLICK_COUNT;
    if (i != old) {
        sel = i;
        host_row(old);
        host_row(i);
    }
#ifdef TERM_TEST
    strcpy((char *)crow, "TERM HOSTS SEL ");
    crow[15] = hexd[i];
    crow[16] = 0;
    LogText((char *)crow);
#endif
    return 0;
}

/* Term > About Term (here for room in main RAM, V112) */
void o_about(void)
{
    message("Veranda Term 1.1", "ANSI, Telnet, TCP, XMODEM. MIT licence");
    LogText("TERM ABOUT");
}

/* (V149) the status bar: what the line is doing at its left, the port
   and the rate at its right, in the UI font, as the SDK's vr_win_status
   draws a window's (vrwin.c) for the window of 80 x 58 cards from card
   row 2 with 2 status rows: the band 465-479 (the line over it at 464,
   frame()'s), the right text ending at 631, the left text from 6, cut to
   611 pixels less the right text's width; fields apart by a gap */
static char st[100], sr[24], nb[12];
static unsigned char sn;

static void more(const char *s)         /* on in the same field */
{
    while (*s && sn < sizeof st - 1)
        st[sn++] = *s++;
    st[sn] = 0;
}

static void add(const char *s)          /* a field */
{
    if (sn)
        more("    ");
    more(s);
}

static void num(unsigned int v)
{
    *put_num(nb, v) = 0;
    more(nb);
}

/* (V194) the bar drawn only when its text changes, and then only the
   characters that changed. It was cleared and drawn whole every second
   (term.c's tick) and at every call: on a real monitor the whole text
   blinked once a second while nothing changed. Now: the same texts as
   drawn, nothing; the right text changed, or st_full (term.c: the frame
   drawn, a desk accessory), the whole bar; else the characters from the
   first that differs: when the old and new ones up to the last that
   differs are as wide (the online time's digits), that span cleared and
   drawn, else from there to the end of the left text's room. (Its own
   drawing, no longer vr_win_status's: vrwin.c's other calls cost
   overlay 3 2 KB.) */
static char ost[100], osr[24];

static unsigned int wid(const char *s, unsigned char n)
{
    unsigned int w = 0;
    while (n--)
        w += GetCharWidth(*s++);
    return w;
}

/* n characters of s at x, through stbuf (below $A000) */
static void run(const char *s, unsigned char n, unsigned int x)
{
    unsigned char m;
    while (n) {
        m = n < sizeof stbuf ? n : sizeof stbuf - 1;
        memcpy(stbuf, s, m);
        stbuf[m] = 0;
        WPutString(stbuf, x, 466 + baselineOffset);
        x += wid(s, m);
        s += m;
        n -= m;
    }
}

static void draw_status(void)
{
    unsigned char k, j, n, no;
    unsigned int x, w, wr, end;
    UseFont(FONT_UI);
    wr = wid(sr, strlen(sr));
    for (n = 0, w = 0; st[n] && (w += GetCharWidth(st[n])) <= 611 - wr; ++n)
        ;
    st[n] = 0;                          /* (cut to its room) */
    SetPattern(0);
    if (st_full || strcmp(sr, osr)) {
        WRectangle(0, 465, 639, 479);
        run(sr, strlen(sr), 631 - wr);
        run(st, n, 6);
        st_full = 0;
#ifdef TERM_TEST
        ++st_draws;
#endif
    } else if (strcmp(st, ost)) {
        no = strlen(ost);
        for (k = 0; st[k] && st[k] == ost[k]; ++k)
            ;
        j = n;
        if (n == no)
            while (j > k && st[j - 1] == ost[j - 1])
                --j;
        x = 6 + wid(st, k);
        if (n == no && (w = wid(st + k, j - k)) == wid(ost + k, j - k))
            end = x + w;                /* (that span only) */
        else {
            j = n;
            end = 617 - wr;             /* (to the end of the room) */
        }
        if (end > x)
            WRectangle(x, 465, end - 1, 479);
        run(st + k, j - k, x);
#ifdef TERM_TEST
        ++st_parts;
#endif
    }
    UseSystemFont();
    strcpy(ost, st);
    strcpy(osr, sr);
}

void o_status(void)
{
    unsigned int t;
    char *p;
    sn = 0;
    st[0] = 0;
    if (tcp) {                          /* (V112) */
        add("TCP ");
        more(target);
        if (tcp != TCP_OPEN)
            more(tcp < TCP_OPEN ? ", connecting" : ", closing");
    }
    if (nouart && cfg.backend == 0)
        add("No serial card");
    else if (online) {
        add("Online ");
        t = (ser_frames - online_since) / 60;
        p = put2(nb, t / 3600);
        *p++ = ':';
        p = put2(p, t / 60 % 60);
        *p++ = ':';
        *put2(p, t % 60) = 0;
        more(nb);
    } else if (!tcp)
        add(syncing ? "Finding the modem" : dialing ? "Dialling" : hangup_state ? "Hanging up" : "Offline");
    if (tn_on)
        add("Telnet");
    else if (tcp && tcp_raw)
        add("Raw TCP");
    if (cfg.echo && !tn_echo)
        add("Local echo");
    if (capfh)
        add("Capture");
    if (sendfh)
        add("Sending a file");
    if (xm_active) {
        add("XMODEM block ");
        num(xm_blocks);
    }
    if (vt_back) {
        add("Back ");
        num(vt_back);
        more(" of ");
        num(vt_hist);
    }
    if (ser_lost || ser_oe) {
        add("Lost ");
        num(ser_lost + ser_oe);
    }
    if (cfg.backend)
        p = put_str(sr, "Script");
    else {
        p = put_str(sr, "$9F");
        *p++ = hexd[cfg.port >> 4];
        *p++ = hexd[cfg.port & 15];
    }
    *put_str(put_num(put_str(p, "    "), bauds[cfg.baud]), "00 8N1") = 0;
    dispBufferOn = ST_WR_FORE;
    draw_status();
#ifdef TERM_TEST
    if (vt_back) {                      /* (gate term: the scrollback's place) */
        strcpy((char *)crow, "TERM STATUS ");
        strncat((char *)crow, st, 60);
        LogText((char *)crow);
    }
#endif
}
