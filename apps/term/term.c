/* Veranda Term: a terminal for a serial port with a Wi-Fi modem behind it
   (a 16C550 UART on the expansion bus, AT commands, then Telnet BBSes).

   The screen (Sunroom, V149): Veranda's menu bar with the window's title
   (the BBS or host) in it, 80 x 55 cells of 8 x 8 (vt.c) under a card
   row of margin, and a status bar at the bottom in the UI font (the
   connection, the online time, Telnet, capture, XMODEM, the scrollback
   position; the port and the line at its right). Pages (settings, the
   address book, the hosts) are drawn in the window and give it back.

   Data comes in through the interrupt (the SDK's vrser.s, V98) into an 8 KB ring; the main
   loop (appMain) takes it, passes it through Telnet and XMODEM to the
   screen, and draws. Keys go to the host (keyVector), PgUp and PgDn move
   through the scrollback, F7 is the session menu.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <scrap.h>
#include <vrpath.h>
#include <theme.h>
#include <vrwin.h>
#include "term.h"
#include "net.h"

struct settings cfg = {
    'V', 2, 0xE0, 4, 4, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,     /* (V91: the TexElec card's 14.7456 MHz; V94: I off) */
    "ATV1", "ATI;ATI2", "time.nist.gov:13"
};
const unsigned int bauds[] = { 3, 12, 24, 48, 96, 192, 384, 576, 1152 };        /* hundreds */

const unsigned int xtals[] = { 1152, 2304, 4608, 5000, 9216, 10000 };          /* MHz / 1600 */


unsigned char font[2048];
unsigned char rxbuf[256];
unsigned char restart;          /* the settings changed the port */
static unsigned char ovl;       /* the overlay's bank (ui.c) */
unsigned char term_ovl2;        /* overlay 2's (sync.c: the modem's rate, the date, V94) */
#define ovl2 term_ovl2
static unsigned char ovl3;      /* overlay 3's (hosts.c: the Hosts page, V112) */

/* the modem's rate looked for (V94, sync.c); its end: what waited */
static void sync_start(void)
{
    MAPBANK(ovl2);
    o_sync();
    status();
}

static void sync_done(void)
{
    LogText("TERM MODEM");
    if (dialing == 4)
        dial_go();
    status();
}
static unsigned char mainbank;          /* the ring, the model (2), the scrollback */
static unsigned char hbanks;
unsigned char nouart;
static char host[48];                   /* the window's title */
static char line[COLS + 1];

static void quit(void);

/*---------------------------------------------------------------
  the font: the X16's own CP437 set, from ROM bank 6 (the charsets'
  bank: found by its glyph 1, the smiley, at a 2 KB boundary)
 ---------------------------------------------------------------*/
static const unsigned char smiley[8] = { 0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E };

static unsigned char load_font(void)
{
    unsigned char keep, ok = 0;
    unsigned int a;
    asm("sei");                 /* bank 6 has no interrupt vectors */
    keep = *(unsigned char *)1;
    *(unsigned char *)1 = 6;
    for (a = 0xC000; a; a += 0x800)
        if (!memcmp((void *)(a + 8), smiley, 8)) {
            memcpy(font, (void *)a, 2048);
            ok = 1;
            break;
        }
    if (!ok)
        memcpy(font, (void *)0xC800, 2048);    /* (some 8 x 8 set) */
    *(unsigned char *)1 = keep;
    asm("cli");
    return ok;
}

/*---------------------------------------------------------------
  the window
 ---------------------------------------------------------------*/
void put_text(const char *s, unsigned char x, unsigned int y, unsigned char flags)
{
    unsigned char n = strlen(s);
    if (n > COLS - x)
        n = COLS - x;
    if (n)
        PutCards((void *)s, font, x, n, y, flags);
}

/* the window's title: in the menu bar after its items (vrwin.h; the
   text fills the screen under it, as Paint's picture: V147) */
static unsigned int barend;
static const char *ttl = "Veranda Term";

void title(const char *s)
{
    ttl = s;
    vr_bar_title(s, barend);
#ifdef TERM_TEST
    strcpy(line, "TERM TITLE ");
    strncat(line, s, 40);
    LogText(line);
#endif
}

char *put_num(char *p, unsigned int v)
{
    char t[6];
    unsigned char n = 0;
    do {
        t[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    while (n)
        *p++ = t[--n];
    return p;
}

char *put_str(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    return p;
}

char *put2(char *p, unsigned char v)
{
    *p++ = '0' + v / 10;
    *p++ = '0' + v % 10;
    return p;
}

const char hexd[] = "0123456789ABCDEF";

unsigned char capfh;
unsigned char sendfh;
static unsigned int last_sec;
unsigned char st_full = 1;
char stbuf[40];
#ifdef TERM_TEST
unsigned int st_draws, st_parts;
#endif

/* the status bar (hosts.c's o_status, overlay 3: V149's room); called
   from overlay 2 too (tcp.c), so the bank mapped before comes back */
void status(void)
{
    unsigned char k = *(unsigned char *)0;
    MAPBANK(ovl3);
    o_status();
    MAPBANK(k);
}

static void frame(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 15, 639, 479);
    WHorizontalLine(0xFF, 0, 639, 15);
    WHorizontalLine(0xFF, 0, 639, STATY);
    st_full = 1;
    status();
}

/*---------------------------------------------------------------
  dialog boxes
 ---------------------------------------------------------------*/
struct askdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;     /* DBVARSTR: the prompt (r6) */
    unsigned char t2, x2, y2, reg2, max;  /* DBGETSTRING (r5) */
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static struct askdlg askbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 20,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

struct msgdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2;
    unsigned char ok, okx, oky;
    unsigned char b2, b2x, b2y;
    unsigned char end;
};
static const struct msgdlg msgbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    OK, DBI_X_0, DBI_Y_2,
    0
};
static const struct msgdlg yesnobox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    YES, DBI_X_0, DBI_Y_2,
    NO, DBI_X_2, DBI_Y_2,
    0
};

/* the texts copied below $A000 (the overlay's are above) */
char msga[48], msgb[48];        /* (V112: tcp.c and hosts.c fill them too) */

static void texts(const char *a, const char *b)
{
    strncpy(msga, a, sizeof msga - 1);
    strncpy(msgb, b, sizeof msgb - 1);
    r5 = (unsigned int)msga;
    r6 = (unsigned int)msgb;
}

/* FOpen with a name from anywhere (the overlay's) */
unsigned char fopen_any(const char *name, unsigned char mode)
{
    static char n[20];
    strncpy(n, name, sizeof n - 1);
    return FOpen(n, mode);
}

/* Term's own file (TERM.CFG, TERM.BOOK) in the system's data folder,
   /VERANDA/.SYSTEM, else in the current folder (no /VERANDA: as before;
   DECISIONS V71) */
unsigned char fopen_sys(const char *name, unsigned char mode)
{
    unsigned char h;
    strcpy(scrap_path, VR_DATAPATH);
    strcat(scrap_path, name);
    h = FOpen(scrap_path, mode);
    if (h >= 2 && h <= 9 && dosStatus < 20)
        return h;
    if (h >= 2 && h <= 9)
        FClose(h);
    return fopen_any(name, mode);
}

void message(const char *a, const char *b)
{
    texts(a, b);
    DoDlgBox((void *)&msgbox);
}

#ifdef TERM_TEST
static unsigned char test_box;  /* a yes/no box is open (the test's player waits) */
static unsigned char test_boxed; /* one was */
#endif

/* msga and msgb in a box (V112: TCP's, filled in overlay 2) */
void msg_box(void)
{
    r5 = (unsigned int)msga;
    r6 = (unsigned int)msgb;
#ifdef TERM_TEST
    test_box = 1;
#endif
    DoDlgBox((void *)&msgbox);
#ifdef TERM_TEST
    test_box = 0;
    test_boxed = 1;
#endif
}

unsigned char yesno(const char *a, const char *b)
{
    unsigned char r;
    texts(a, b);
#ifdef TERM_TEST
    test_box = 1;
#endif
    r = DoDlgBox((void *)&yesnobox) == YES;
#ifdef TERM_TEST
    test_box = 0;
    test_boxed = 1;
#endif
    return r;
}

/* a string into buf (max characters; buf keeps what it had as the
   default); 0: cancelled */
unsigned char ask(const char *prompt, char *buf, unsigned char max)
{
    unsigned char r;
    askbox.max = max;
    texts(prompt, "");
    r5 = (unsigned int)buf;
    r = DoDlgBox((void *)&askbox);
    return r == OK || r == DBGETSTRING;
}

static void menus_off(void)
{
    GotoFirstMenu();
    title(ttl);                         /* (GotoFirstMenu draws the bar again) */
}

/*---------------------------------------------------------------
  capture and sending a file
 ---------------------------------------------------------------*/
static unsigned char capbuf[256];
static unsigned int caplen;
static char fname[33] = "CAPTURE.TXT";

static void cap_flush(void)
{
    if (capfh && caplen) {
        FWrite(capfh, capbuf, caplen);
        caplen = 0;
    }
}

void capture_byte(unsigned char c)
{
    if (!capfh)
        return;
    capbuf[caplen++] = c;
    if (caplen == sizeof capbuf)
        cap_flush();
}

static unsigned char capture_start(const char *name)
{
    capfh = FOpen((void *)name, 'w');
    if (capfh < 2) {
        capfh = 0;
        return 1;
    }
    caplen = 0;
    status();
    return 0;
}

static void capture_stop(void)
{
    if (!capfh)
        return;
    cap_flush();
    FClose(capfh);
    capfh = 0;
    status();
}

static unsigned char sendbuf[128];
static unsigned char sendpos, sendlen;

static void send_pump(void)
{
    while (sendfh) {
        if (sendpos == sendlen) {
            sendlen = FRead(sendfh, sendbuf, sizeof sendbuf);
            sendpos = 0;
            if (!sendlen) {
                FClose(sendfh);
                sendfh = 0;
                status();
                return;
            }
        }
        if (tx_room() < 2)
            return;
        net_send(sendbuf[sendpos++]);
    }
}

static void m_capture(void)
{
    menus_off();
    if (capfh) {
        capture_stop();
        return;
    }
    if (!ask("Capture to the file:", fname, 32) || !fname[0])
        return;
    if (capture_start(fname))
        message("Cannot create", fname);
}

static void m_send(void)
{
    menus_off();
    if (sendfh)
        return;
    fname[0] = 0;
    if (!ask("Send the text file:", fname, 32) || !fname[0])
        return;
    sendfh = FOpen(fname, 'r');
    if (sendfh < 2) {
        sendfh = 0;
        message("Cannot open", fname);
        return;
    }
    sendpos = sendlen = 0;
    status();
}

static void m_download(void)
{
    menus_off();
    if (xm_active) {
        xm_cancel();
        return;
    }
    fname[0] = 0;
    if (!ask("XMODEM: receive into the file:", fname, 32) || !fname[0])
        return;
    if (xm_start(fname))
        message("Cannot create", fname);
}

/*---------------------------------------------------------------
  the script back-end (gates): TERM.IN into RAM banks, played at the
  baud rate when "dialled"
 ---------------------------------------------------------------*/
static unsigned char sbanks;

static void script_load(void)
{
    unsigned char h, b;
    unsigned int n, a = 0xA000;
    unsigned int total = 0;
    if (!sbanks) {
        sbanks = BankAlloc(9);          /* 64 KB of script, 8 KB of log */
        if (!sbanks)
            return;
        ser_logbank = sbanks + 8;
    }
    h = FOpen("TERM.IN", 'r');
    if (h < 2)
        return;
    b = sbanks;
    while ((n = FRead(h, rxbuf, sizeof rxbuf)) != 0 && total < 65000u) {
        BankCopy(rxbuf, (void *)a, n, 0, b);
        total += n;
        a += n;
        if (a >= 0xC000) {
            a -= 0x2000;
            ++b;
        }
    }
    FClose(h);
    asm("sei");
    ser_sbank = sbanks;
    ser_saddr = 0xA000;
    ser_send = total;
    asm("cli");
}

/*---------------------------------------------------------------
  connecting
 ---------------------------------------------------------------*/
static void page_open(unsigned char p);
static char dialbuf[48] = "";
static char docaddr[41];

static void dial(const char *name, const char *addr)
{
    if (cfg.backend == 1) {
        ser_rate = bauds[cfg.baud] / 6;
        if (!ser_rate)
            ser_rate = 1;
        script_load();
    }
    strncpy(host, name, sizeof host - 1);
    title(host);
    net_dial(addr);
}

static void m_dial(void)
{
    menus_off();
    if (online || tcp) {
        message("Online already:", "hang up first.");
        return;
    }
    if (!ask("Dial host:port or an AT command:", dialbuf, 40) || !dialbuf[0])
        return;
    dial(dialbuf, dialbuf);
}

/* (V112) Connection > Connect...: the Hosts page (hosts.c); a TCP
   session through the modem's command mode (tcp.c), its events here */
static void tcp_connect(void)
{
    strncpy(host, msga, sizeof host - 1);
    title(host);
    MAPBANK(ovl2);
    o_tcp_start(nouart | cfg.backend);
}

static void tcp_tick(void)
{
    unsigned char i, n;
    for (i = 0; i < 8; ++i) {
        MAPBANK(ovl2);
        n = o_tcp_poll();
        if (n)
            net_rx(rxbuf, n);
        if (tcp_ev) {
            MAPBANK(ovl2);
            o_tcp_event();              /* (the status line, a box) */
        }
        if (!n)
            break;
    }
}

static void m_connect(void)
{
    menus_off();
    if (online || dialing || tcp) {
        message("Online:", "disconnect first.");
        return;
    }
    page_open(3);
}

static void m_hangup(void)
{
    menus_off();
    net_hangup();
}

/* the clock: the daytime service (cfg.timehost) through the modem, or a
   modem status line with a date in it; set in the RTC (SetClock) */
static unsigned char clock_pending;

/* (in overlay 2 with the date's parsing, sync.c: V112's room) */
static void clock_offer(void)
{
    MAPBANK(ovl2);
    o_clock_offer();
}

void net_dropped(void)
{
    if (clock_pending) {
        clock_pending = 0;
        if (net_time_ok)
            clock_offer();
        else
            message("No time came from", cfg.timehost);
    }
}

static void m_clock(void)
{
    menus_off();
    if (online || dialing || tcp) {
        message("Online:", "hang up first.");
        return;
    }
    net_time_ok = 0;
    clock_pending = 1;
    dial(cfg.timehost, cfg.timehost);
}

/* modem status: the info commands (cfg.info, ';' between them), one a
   second and a half, their answers in the window */
unsigned char info_on;          /* 1 asked, 2 under way (sync.c's o_info_pump, V112) */

static void m_status(void)
{
    menus_off();
    if (online || dialing || tcp) {
        message("Online:", "hang up first.");
        return;
    }
    vt_puts("\r\n\033[1m[ modem status ]\033[0m\r\n");
    info_on = 1;
    net_time_ok = 0;
}

/*---------------------------------------------------------------
  pages in the window: settings, the address book
 ---------------------------------------------------------------*/
static unsigned char page;              /* 0 none, 1 settings, 2 the address book, 3 hosts */
static void page_draw(void);

static void page_open(unsigned char p)
{
    page = p;
    vt_hold = 1;
    vt_mapclear();
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, TY, 639, STATY - 1);
    page_draw();
}

static void page_close(void)
{
    page = 0;
    vt_hold = 0;
    title(host[0] ? host : "Veranda Term");
    vt_redraw();
}

static void page_draw(void)
{
    if (page == 3) {
        MAPBANK(ovl3);
        o_hosts_draw();
    } else {
        MAPBANK(ovl);
        o_page_draw(page);
    }
    if (page > 1) {                     /* (V195) the buttons */
        MAPBANK(ovl2);
        o_btns(page == 3);
    }
}

static void page_done(unsigned char p, unsigned char r);

/* k: a key (0: a click, V195: the address book's and the Hosts page's
   rows and buttons; the settings page takes none) */
static void page_key(unsigned char k)
{
    unsigned char r, p = page;
    if (p == 3) {
        MAPBANK(ovl3);
        r = k ? o_hosts_key(k) : o_hosts_click();
    } else {
        MAPBANK(ovl);
        r = p == 1 ? (k ? o_settings_key(k) : 0) : k ? o_book_key(k) : o_book_click();
    }
    page_done(p, r);
}

/* (V195) otherPressVec: a press (not its release) on a page */
void page_press(void)
{
    if (page && !(mouseData & 0x80))
        page_key(0);
}

static void page_done(unsigned char p, unsigned char r)
{
    static char n[25], a[41];
    if (p == 2 && r == 2)
        o_book_entry(n, a);             /* (overlay 1 still mapped) */
    if (!r)
        return;
    page_close();
    if (p == 3) {
        if (r == 2)
            tcp_connect();
        return;
    }
    if (p == 1 && restart && !tcp) {
        restart = 0;
        nouart = ser_start();
        sync_start();                   /* the modem's rate (V94) */
    }
    if (r == 2 && !online)
        dial(n, a);
    status();
}

/* a page's row r: s in cells 1-78 (an 8-pixel margin each side) */
static void fill(const char *s)
{
    unsigned char n = strlen(s);
    memset(line, ' ', COLS - 2);
    memcpy(line, s, n > COLS - 2 ? COLS - 2 : n);
    line[COLS - 2] = 0;
}

void row_text(unsigned char r, const char *s, unsigned char flags)
{
    fill(s);
    put_text(line, 1, TY + 8 * r, flags);
}

/* (V149) s in the UI font, its top at y (copied below $A000: rxbuf is
   free while a page shows) */
void ui_text(const char *s, unsigned int x, unsigned int y, unsigned char bold)
{
    strncpy((char *)rxbuf, s, 120);
    rxbuf[120] = 0;
    UseFont(FONT_UI);
    currentMode = bold ? SET_BOLD : 0;
    WPutString(rxbuf, x, y + baselineOffset);
    currentMode = 0;
    UseSystemFont();
}

/* a page's row of 16 lines from y (a list's: LISTTOP + 16 i): s in cells
   1-78, the chosen one inverted */
void list_row(unsigned int y, const char *s, unsigned char sel)
{
    SetPattern(0);
    WRectangle(8, y, 631, y + 15);
    fill(s);
    put_text(line, 1, y + 4, 0);
    if (sel)
        WInvertRectangle(8, y, 631, y + 15);
}

/* (V195) a list page's mouse parts (the address book, the Hosts page;
   their buttons are drawn by overlay 2's o_btns): where a click is */
/* the button under the pointer (0-4), else 255 */
unsigned char btn_at(void)
{
    unsigned char c = mouseXPos >> 3, i;
    if (mouseYPosW < BTNY || mouseYPosW >= BTNY + 16)
        return 255;
    for (i = 0; i < 5; ++i)
        if (c >= 1 + 13 * i && c < 1 + 13 * i + BTNW)
            return i;
    return 255;
}

/* the list's row under the pointer (rows of 16 lines from LISTTOP, x
   8-631), else 255 */
unsigned char row_at(unsigned char n)
{
    unsigned int y = mouseYPosW, x = mouseXPos;
    if (y < LISTTOP || y >= LISTTOP + 16 * n || x < 8 || x > 631)
        return 255;
    return (y - LISTTOP) >> 4;
}

/* a page's heading: its title in bold, a line of help, a rule under them */
void page_head(const char *t, const char *help)
{
    ui_text(t, 8, TY + 4, 1);
    ui_text(help, 8, TY + 20, 0);
    WHorizontalLine(0xFF, 8, 631, TY + 37);
}

static void m_settings(void)
{
    menus_off();
    page_open(1);
}

static void m_book(void)
{
    menus_off();
    if (online) {
        message("Online:", "hang up first.");
        return;
    }
    page_open(2);
}

static void m_clear(void)
{
    menus_off();
    vt_reset();
    vt_render();
}

static void m_about(void)
{
    menus_off();
    MAPBANK(ovl3);
    o_about();                          /* (hosts.c: room, V112) */
}

/* a desk accessory: the serial port's interrupts off while it runs (its
   memory is put aside, the interrupt routine with it), RTS down */
struct filedlg {
    unsigned char pos;
    unsigned char f, fx, fy;
    unsigned char op, opx, opy;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct filedlg filebox = {
    DEF_DB_POS | 1,
    DBGETFILES, 4, 4,
    OPEN, DBI_X_2, DBI_Y_0,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};
static char daname[17];

static void m_desk(void)
{
    unsigned char r;
    menus_off();
    daname[0] = 0;
    r5 = (unsigned int)daname;
    r7L = DESK_ACC;
    r10 = 0;
    vr_cd(VR_APPS);                     /* (with the applications: V71) */
    r = DoDlgBox((void *)&filebox);
    if (r == DBGETFILES) {
        vr_cdback();
        message("There are no desk accessories", "with the applications.");
        return;
    }
    if (r != OPEN || !daname[0]) {
        vr_cdback();
        return;
    }
    ser_pause();
    r = GetFile(daname, 0, 0, 0, 0);
    ser_resume();
    vr_cdback();
    st_full = 1;                        /* (V194: drawn whole again) */
    status();
    if (r)
        message("Cannot open", daname);
}

static void m_quit(void)
{
    menus_off();
    quit();
}

/* options/copy screen: the window's text on the clipboard (the Text
   Scrap, scrap.h; DECISIONS V54): each row without its trailing spaces
   and a CR, the empty rows at the end left out, characters outside
   ASCII as '?' (the window shows CP437) */
unsigned char crow[COLS + 1];
char scrap_path[40];            /* the scrap library's path (it is in the overlay) */

/* row r's characters in crow, without its trailing spaces (the overlay
   mapped again: the rows are in vt's banks) */
unsigned char crow_len(unsigned char r)
{
    unsigned char n = COLS;
    vt_cell_text(r, crow);
    MAPBANK(ovl);
    while (n && crow[n - 1] == ' ')
        --n;
    return n;
}

/* (the scrap library is compiled into the overlay, with o_copy_screen:
   the resident program had no room left, DECISIONS V71) */
static void copy_screen(void)
{
    MAPBANK(ovl);
    o_copy_screen();
}

static void m_copy(void)
{
    menus_off();
    copy_screen();
}

/*---------------------------------------------------------------
  the session menu (F7): hang up, download, capture, back to the shell
 ---------------------------------------------------------------*/
struct sessdlg {
    unsigned char pos;
    unsigned char t1, x1, y1; const char *s1;
    unsigned char t2, x2, y2; const char *s2;
    unsigned char t3, x3, y3, reg3, max;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct sessdlg sessbox = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, "Session: a letter and Return",
    DBTXTSTR, TXT_LN_X, TXT_LN_2_Y, "D hang up  X download  C capture  Q quit",
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y + 8, 0x0C, 1,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

static void session(void)
{
    static char k[2];
    unsigned char r;
    k[0] = 0;
    r5 = (unsigned int)k;
    r = DoDlgBox((void *)&sessbox);
    if (r != DBGETSTRING && r != OK)
        return;
    switch (k[0] | 0x20) {
    case 'd': net_hangup(); break;
    case 'x': m_download(); break;
    case 'c': m_capture(); break;
    case 'q': quit(); break;
    }
}

/*---------------------------------------------------------------
  the menus
 ---------------------------------------------------------------*/
struct item { const char *text; unsigned char type; void *p; };
struct menu5 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[5]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };

/* the menus in the Veranda look (DECISIONS V74, V79): the first is
   Term's own (about, a desk accessory, quit). Sunroom's lists (V146,
   V149): $1F in front of an item starts a group (a dotted line above
   it), a key after a tab is shown at the right: the Alt keys key()
   takes */
#define IH 14
static struct menu3 mterm = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { "About Term", MENU_ACTION, m_about }, { "\x1f" "Desk accessory...", MENU_ACTION, m_desk },
    { "\x1f" "Quit\tAlt Q", MENU_ACTION, m_quit } } };
static struct menu3 mfile = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { "Capture on/off", MENU_ACTION, m_capture }, { "Send text file...", MENU_ACTION, m_send },
    { "\x1f" "XMODEM download...\tAlt X", MENU_ACTION, m_download } } };
static struct menu6 mconn = { 14, 14 + 6 * IH, 0, 0, VERTICAL | 6, {
    { "Connect...", MENU_ACTION, m_connect }, { "Dial...\tAlt D", MENU_ACTION, m_dial },
    { "Address book", MENU_ACTION, m_book }, { "\x1f" "Disconnect / hang up\tAlt H", MENU_ACTION, m_hangup },
    { "\x1f" "Modem status", MENU_ACTION, m_status }, { "Clock from network", MENU_ACTION, m_clock } } };
static struct menu3 mopts = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { "Settings...", MENU_ACTION, m_settings }, { "\x1f" "Clear screen", MENU_ACTION, m_clear },
    { "Copy screen", MENU_ACTION, m_copy } } };
static struct menu4 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { "Term", SUB_MENU, &mterm }, { "File", SUB_MENU, &mfile }, { "Connection", SUB_MENU, &mconn },
    { "Options", SUB_MENU, &mopts } } };
static const char *const barnames[4] = { "Term", "File", "Connection", "Options" };

/* (V212) strw and layout run once, at the start: in overlay 3 (main's
   call maps it), for the resident program's room */
#pragma code-name (push, "OVERLAY3")
#pragma rodata-name (push, "OVL3RO")

/* an item's width: a tab 24 pixels, $1F nothing (shell/look3.c's mwidth) */
static unsigned int strw(const char *s)
{
    unsigned int w = 0;
    unsigned char c;
    while ((c = *s++) != 0)
        w += c == 9 ? 24 : c == 0x1F ? 0 : GetCharWidth(c);
    return w;
}

#pragma code-name (pop)
#pragma rodata-name (pop)
static unsigned int barx[4];    /* the bar's items' middles (the test build clicks them) */
#pragma code-name (push, "OVERLAY3")
#pragma rodata-name (push, "OVL3RO")

/* the lists' widths in the UI font (the menus' font, theme_menus); the
   kernel puts each under its bar item (vr_bar_end: where the items are) */
static void layout(void)
{
    static unsigned int *const lefts[4] = { &mterm.left, &mfile.left, &mconn.left, &mopts.left };
    static unsigned int *const rights[4] = { &mterm.right, &mfile.right, &mconn.right, &mopts.right };
    static struct item *const items[4] = { mterm.i, mfile.i, mconn.i, mopts.i };
    static const unsigned char nitems[4] = { 3, 3, 6, 3 };
    unsigned int b, w, m;
    unsigned char i, j;
    for (i = 0; i < 4; ++i) {
        b = vr_bar_end(barnames, i);
        barx[i] = (b + vr_bar_end(barnames, i + 1)) >> 1;
        UseFont(FONT_UI);
        for (m = 0, j = 0; j < nitems[i]; ++j)
            if ((w = strw(items[i][j].text)) > m)
                m = w;
        *lefts[i] = b;
        *rights[i] = b + m + 16;
    }
    mbar.right = barend = vr_bar_end(barnames, 4);
    UseSystemFont();
}
#pragma code-name (pop)
#pragma rodata-name (pop)

/*---------------------------------------------------------------
  keys
 ---------------------------------------------------------------*/
static void send_str(const char *s)
{
    while (*s)
        net_send(*s++);
}

static void echo(unsigned char c)
{
    if (cfg.echo && !tn_echo) {
        vt_put(c);
        if (c == 13 && !cfg.crin)
            vt_put(10);
    }
}

static void key(void)
{
    unsigned char k = keyData, m = keyDataMods;
    if (page) {
        page_key(k);
        return;
    }
    if (k == KEY_PGUP && !(m & 2)) {
        vt_view(ROWS / 2);
        return;
    }
    if (k == KEY_PGDN && !(m & 2)) {
        vt_view(-(int)(ROWS / 2));
        return;
    }
    if (vt_back) {
        vt_view(-(int)vt_back);         /* any other key: live again */
        if (k == KEY_END)
            return;
    }
    if (k == KEY_F7 && !(m & 2)) {
        session();
        return;
    }
    if ((m & 4) && k >= 0x80) {         /* Alt + a letter: our shortcuts */
        switch (k & 0x7F) {
        case 'd': m_dial(); break;
        case 'h': m_hangup(); break;
        case 'x': m_download(); break;
        case 'q': quit(); break;
        }
        return;
    }
    if (k == 13) {
        echo(13);
        if (cfg.ret == 2)
            net_send(10);
        else {
            net_send(13);
            if (cfg.ret == 1)
                net_send(10);
            else if (tn_on && !(tn_bin & 2))
                net_send(0);            /* Telnet's CR NUL */
        }
        return;
    }
    if (m & 2) {                        /* Ctrl + a letter */
        net_send(k & 0x1F);
        return;
    }
    if (m & KEYM_ARROW) {
        send_str(k == KEY_UP ? "\033[A" : k == KEY_DOWN ? "\033[B" : k == KEY_RIGHT ? "\033[C" : "\033[D");
        return;
    }
    switch (k) {
    case 8: k = cfg.bs ? 127 : 8; break;
    case KEY_HOME: send_str("\033[H"); return;
    case KEY_END: send_str("\033[F"); return;
    case KEY_INSERT: send_str("\033[2~"); return;
    case KEY_DELETE: send_str("\033[3~"); return;
    case KEY_F1: send_str("\033OP"); return;
    case KEY_F2: send_str("\033OQ"); return;
    case KEY_F3: send_str("\033OR"); return;
    case KEY_F4: send_str("\033OS"); return;
    case KEY_STOP: k = 3; break;
    case KEY_ESC: case KEY_TAB: break;
    default:
        if (k < 32 || (k >= 0x80 && k < 0xA0))
            return;
    }
    echo(k);
    net_send(k);
}

/*---------------------------------------------------------------
  the main loop
 ---------------------------------------------------------------*/
#ifdef TERM_TEST
static void test_start(void);
static void test_tick(void);
#endif

static void tick(void)
{
    unsigned int n;
    unsigned char i, got = rx_total;
    term_wake();                        /* (after the switcher: V91) */
    if (tcp > TCP_WAIT || (tcp && !syncing))
        tcp_tick();                     /* (V112: the line is tcp.c's) */
    else for (i = 0; i < 8; ++i) {
        n = ser_get(rxbuf, sizeof rxbuf);
        if (!n)
            break;
        net_rx(rxbuf, n);
    }
    if (syncing) {                      /* (V94) */
        MAPBANK(ovl2);
        if (o_sync_tick())
            sync_done();
    }
    net_tick();
    send_pump();
    if (info_on) {
        MAPBANK(ovl2);
        o_info_pump();
    }
    if (!vt_hold && !vt_back)
        vt_pass(got != (unsigned char)rx_total);
    /* the I-beam over the terminal's text, the arrow over the pages and
       elsewhere (DECISIONS V51) */
    SetPointer(!vt_hold && mouseYPosW >= TY && mouseYPosW < TY + ROWS * 8 ? PTR_IBEAM : PTR_ARROW);
    if (ser_frames - last_sec >= 60 && menuNumber == 0 && !vt_hold) {
        last_sec = ser_frames;
        status();
    }
#ifdef TERM_TEST
    test_tick();
#endif
}

static void quit(void)
{
    unsigned int n;
    capture_stop();
    xm_cancel();
    if (tcp > TCP_WAIT) {               /* (V112: the modem's connection closed, */
        sends("ATZ\r");                 /* its profile back) */
        n = ser_frames;
        while (!ser_sent() && ser_frames - n < 30)
            ;
    }
    ser_stop();
    intFirstVector = 0;
    EnterDeskTop();
}

int main(void)
{
    unsigned char b, doc = r0L & ST_LD_DATA;    /* (before anything uses r0) */
    dispBufferOn = ST_WR_FORE;
    load_font();
    LoadOverlay(1, 0);
    ovl = r1L;
    LoadOverlay(2, 0);
    ovl2 = r1L;
    LoadOverlay(3, 0);
    ovl3 = r1L;
    MAPBANK(ovl);
    o_load_settings();
    o_book_load();
    hbanks = 16;
    while (!(b = BankAlloc(3 + hbanks)) && hbanks)
        hbanks >>= 1;
    mainbank = b;
    ser_rxbank = b;
    vt_init(b + 1, b + 3, hbanks);
    intFirstVector = VR_FN(SerIrq);
    asideVector = VR_FN(term_aside);    /* (V91) */
#ifdef TERM_TEST
    test_start();
#endif
    if (!cfg.backend && !ser_at(cfg.port)) {
        b = ser_probe();
        if (b)
            cfg.port = b;
    }
    nouart = ser_start();
    frame();
    MAPBANK(ovl3);
    layout();
    MAPBANK(ovl);
    theme_load();
    theme_menus();                      /* the menu bar (V74; black and white: the ANSI colours) */
    DoMenu((void *)&mbar, 0);
    title(ttl);                         /* (in the bar: after DoMenu) */
    keyVector = VR_FN(key);
    otherPressVec = VR_FN(page_press);  /* (V195) */
    appMain = VR_FN(tick);
    LogText(nouart ? "TERM RUNNING (NO UART)" : "TERM RUNNING");
    sync_start();                       /* the modem's rate (V94) */
    vt_render();
    /* started with a .TEL document (Dex's Connect, a double click in the
       shell: DECISIONS V56): dial it */
    MAPBANK(ovl);
    if (doc && o_doc(dialbuf, docaddr)) {
        LogText("TERM DOC");
        LogText(docaddr);
        dial(dialbuf, docaddr);
    }
    vr_home(0);                         /* captures, downloads: /DOCUMENTS (V71) */
    return 0;
}

#ifdef TERM_TEST
#include "../../tests/term_test.c"
#endif
