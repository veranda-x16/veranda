/* Veranda Term: the pages (settings, the address book) and the settings
   file, in a banked overlay (record 1, $A000 of its own RAM bank; term.c
   maps it before every call: the o_ functions). Rules (sdk/docs/GUIDE.md,
   overlays): what goes to the kernel is below $A000 (term.c's message,
   ask and row_text copy their strings), and nothing here calls a resident
   function that maps another bank.

   MIT licence (see LICENSE). */
#pragma code-name ("OVERLAY1")
#pragma rodata-name ("OVL1RO")
#pragma data-name ("OVL1DATA")
#pragma bss-name ("OVL1BSS")
#include <string.h>
#include <scrap.h>
#include "term.h"
#include "net.h"

static const char *const xtaltxt[] = { "1.8432", "3.6864", "7.3728", "8.0", "14.7456", "16.0" };

void o_save_settings(void)
{
    unsigned char h = fopen_sys("TERM.CFG", 'w');
    if (h < 2) {
        message("Cannot write", "TERM.CFG");
        return;
    }
    FWrite(h, &cfg, sizeof cfg);
    FClose(h);
}

void o_load_settings(void)
{
    unsigned char h = fopen_sys("TERM.CFG", 'r');
    if (h < 2)
        return;
    if (FRead(h, rxbuf, sizeof cfg) == sizeof cfg && rxbuf[0] == 'V' && (rxbuf[1] == 1 || rxbuf[1] == 2)) {
        memcpy(&cfg, rxbuf, sizeof cfg);
        if (cfg.version == 1) {         /* (V94) a file from before: its I was the */
            cfg.version = 2;            /* old default, on; the UART's interrupt */
            cfg.uirq = 0;               /* is off now unless chosen again */
        }
    }
    FClose(h);
}

static char *onoff(char *p, unsigned char v)
{
    return put_str(p, v ? "on" : "off");
}

/* (V149) a setting's row: its key in cell 0, its name from cell 3, its
   value from cell 22 (list_row: 16 lines, cells 1-78 of the window) */
static char b[COLS + 1];
static unsigned int r;                  /* (the next row's top) */

static char *row0(char key, const char *name)
{
    memset(b, ' ', 22);
    b[0] = key;
    memcpy(b + 3, name, strlen(name));
    return b + 22;
}

static void row1(char *p)
{
    *p = 0;
    list_row(r, b, 0);
    r += 16;
}

static void group(const char *s)        /* a group's heading, bold */
{
    ui_text(s, 8, r + 8, 1);
    r += 26;
}

static void settings_draw(void)
{
    char *p;
    r = TY + 36;
    page_head("Settings", "A letter changes a setting; Esc or Return goes back. W writes them to TERM.CFG.");
    group("The serial port");
    p = put_str(row0('A', "UART address"), "$9F");
    *p++ = hexd[cfg.port >> 4];
    *p++ = hexd[cfg.port & 15];
    row1(put_str(p, ser_at(cfg.port) ? "   (a 16C550 answers)" : "   (no UART answers here)"));
    row1(put_str(row0('P', "Probe"), "$9F60-$9FF0 by $10 (a second port: +8)"));
    p = put_str(put_num(row0('B', "Baud rate"), bauds[cfg.baud]), "00 8N1, divisor ");
    row1(put_num(p, ser_divisor()));
    row1(put_str(put_str(row0('C', "UART crystal"), xtaltxt[cfg.xtal]), " MHz"));
    row1(put_str(onoff(row0('I', "UART interrupt"), cfg.uirq), "   (VERA's line interrupt reads it anyway)"));
    group("The terminal");
    row1(onoff(row0('E', "Local echo"), cfg.echo));
    row1(put_str(row0('R', "Received CR"), cfg.crin ? "CR LF" : "CR"));
    row1(put_str(row0('T', "Return sends"), cfg.ret == 0 ? "CR" : cfg.ret == 1 ? "CR LF" : "LF"));
    row1(put_str(row0('K', "Backspace sends"), cfg.bs ? "DEL (127)" : "BS (8)"));
    row1(put_str(row0('N', "Telnet"), cfg.telnet == 0 ? "auto (after a host:port dial)" : cfg.telnet == 1 ? "always" : "never"));
    row1(onoff(row0('O', "ANSI colours"), cfg.colour));
    row1(put_str(row0('S', "Scheme"), cfg.scheme ? "dark (the default background black)" : "light (the default background the paper)"));
    group("The modem and the clock");
    row1(put_str(row0('M', "Modem init"), cfg.init));
    row1(put_str(row0('Q', "Status commands"), cfg.info));
    row1(put_str(row0('H', "Time service"), cfg.timehost));
    p = put_str(row0('Z', "Time zone"), "UTC");
    *p++ = cfg.tz < 0 ? '-' : '+';
    p = put2(p, (cfg.tz < 0 ? -cfg.tz : cfg.tz) / 4);
    *p++ = ':';
    p = put2(p, (cfg.tz < 0 ? -cfg.tz : cfg.tz) % 4 * 15);
    row1(put_str(p, "   (+ and - a quarter hour)"));
    row1(put_str(row0('U', "Set the clock"), cfg.autoclock ? "without asking" : "after asking"));
}

/* the address book: some well known Telnet BBSes (from memory: check
   them) and up to eight of the user's own, in TERM.BOOK ("name|host:port"
   a line) */
#define BOOK 16
#define BUILTIN 8
struct entry { char name[25]; char addr[41]; };
struct bentry { const char *name, *addr; };
static const struct bentry builtin[BUILTIN] = {
    { "Vertrauen (Synchronet)", "vert.synchro.net:23" },
    { "Black Flag", "blackflag.acid.org:23" },
    { "20 For Beers", "20forbeers.com:1337" },
    { "Particles!", "particlesbbs.dyndns.org:6400" },
    { "The Oasis (PETSCII)", "oasisbbs.hopto.org:6400" },
    { "Retro Campus", "bbs.retrocampus.com:23" },
    { "Absinthe", "absinthebbs.net:1940" },
    { "Xibalba", "xibalba.l33t.codes:44510" },
};
static struct entry own[BOOK - BUILTIN];
static unsigned char sel;

static const char *bname(unsigned char i)
{
    return i < BUILTIN ? builtin[i].name : own[i - BUILTIN].name;
}

static const char *baddr(unsigned char i)
{
    return i < BUILTIN ? builtin[i].addr : own[i - BUILTIN].addr;
}

void o_book_load(void)
{
    unsigned char h, n = 0, i = 0, f = 0, c;
    unsigned int len, k;
    memset(own, 0, sizeof own);
    sel = 0;                            /* (V112: an overlay's BSS is not cleared) */
    h = fopen_sys("TERM.BOOK", 'r');
    if (h < 2)
        return;
    while ((len = FRead(h, rxbuf, sizeof rxbuf)) != 0)
        for (k = 0; k < len && n < BOOK - BUILTIN; ++k) {
            c = rxbuf[k];
            if (c == '\n' || c == '\r') {
                if (i || f)
                    ++n;
                i = f = 0;
            } else if (c == '|' && !f) {
                f = 1;
                i = 0;
            } else if (!f && i < 24)
                own[n].name[i++] = c;
            else if (f && i < 40)
                own[n].addr[i++] = c;
        }
    FClose(h);
}

static void book_save(void)
{
    unsigned char h, i;
    char *p;
    h = fopen_sys("TERM.BOOK", 'w');
    if (h < 2)
        return;
    for (i = 0; i < BOOK - BUILTIN; ++i)
        if (own[i].addr[0]) {
            p = put_str(put_str((char *)rxbuf, own[i].name), "|");
            p = put_str(p, own[i].addr);
            *p++ = '\n';
            FWrite(h, rxbuf, p - (char *)rxbuf);       /* (below $A000) */
        }
    FClose(h);
}

static const char bk[5] = { 13, 'N', 'E', 'X', 27 };    /* (the buttons' keys) */

/* row i of the list */
static void book_row(unsigned char i)
{
    memset(b, ' ', COLS);
    b[COLS] = 0;
    b[0] = hexd[i];
    if (baddr(i)[0]) {
        memcpy(b + 3, bname(i), strlen(bname(i)));
        memcpy(b + 30, baddr(i), strlen(baddr(i)));
    } else
        memcpy(b + 3, "(free)", 6);
    list_row(LISTTOP + 16 * i, b, i == sel);
}

static void book_draw(void)
{
    unsigned char i;
    page_head("Address book", "Click or 0-9, A-F choose; a double click or Return dials; N new, E edits, X deletes (your own: 8-F).");
    ui_text("Name", 8 + 3 * 8, TY + 48, 1);
    ui_text("Host and port", 8 + 30 * 8, TY + 48, 1);
    for (i = 0; i < BOOK; ++i)
        book_row(i);
}

void o_page_draw(unsigned char page)
{
    if (page == 1)
        settings_draw();
    else
        book_draw();
}


unsigned char o_settings_key(unsigned char k)
{
    unsigned char i;
    if (k >= 'a' && k <= 'z')
        k -= 32;
    switch (k) {
    case 'A':                           /* $9F60, $9F68 ... $9FF8 */
        cfg.port = (cfg.port & 0xF8) + 8;
        if (cfg.port < 0x60)
            cfg.port = 0x60;
        restart = 1;
        break;
    case 'P':
        i = ser_probe();
        if (i) {
            cfg.port = i;
            restart = 1;
        } else
            message("No 16C550 answers at", "$9F60, $9F70 ... $9FF0");
        break;
    case 'B': cfg.baud = (cfg.baud + 1) % NBAUDS; restart = 1; break;
    case 'C': cfg.xtal = (cfg.xtal + 1) % NXTALS; restart = 1; break;
    case 'I': cfg.uirq ^= 1; restart = 1; break;
    case 'E': cfg.echo ^= 1; break;
    case 'R': cfg.crin ^= 1; break;
    case 'T': cfg.ret = (cfg.ret + 1) % 3; break;
    case 'K': cfg.bs ^= 1; break;
    case 'N': cfg.telnet = (cfg.telnet + 1) % 3; break;
    case 'O': cfg.colour ^= 1; break;
    case 'S': cfg.scheme ^= 1; break;
    case 'M': ask("The modem's init string:", cfg.init, 32); break;
    case 'Q': ask("Status commands (; between):", cfg.info, 32); break;
    case 'H': ask("Time service host:port:", cfg.timehost, 40); break;
    case '+': if (cfg.tz < 56) ++cfg.tz; break;
    case '-': if (cfg.tz > -48) --cfg.tz; break;
    case 'U': cfg.autoclock ^= 1; break;
    case 'W': o_save_settings(); break;
    case 13: case 27:
        return 1;
    default:
        return 0;
    }
    settings_draw();
    return 0;
}

unsigned char o_book_key(unsigned char k)
{
    struct entry *e;
    unsigned char i;
    if (k >= 'a' && k <= 'z')
        k -= 32;
    if (k >= '0' && k <= '9')
        sel = k - '0';
    else if (k >= 'A' && k <= 'F')
        sel = k - 'A' + 10;
    else if (k == KEY_UP && sel)
        --sel;
    else if (k == KEY_DOWN && sel < BOOK - 1)
        ++sel;
    else if (k == 13)
        return baddr(sel)[0] ? 2 : 0;
    else if (k == 27)
        return 1; else if (k == 'N' || k == 'E') {
        if (k == 'N')
            for (i = BUILTIN; i < BOOK && own[i - BUILTIN].addr[0]; ++i)
                ;
        else
            i = sel;
        if (i < BUILTIN || i >= BOOK)
            return 0;
        e = &own[i - BUILTIN];
        if (!ask("Name:", e->name, 24) || !ask("host:port:", e->addr, 40))
            return 0;
        sel = i;
        book_save();
    } else if (k == 'X') {
        if (sel < BUILTIN)
            return 0;
        memset(&own[sel - BUILTIN], 0, sizeof own[0]);
        book_save();
    } else
        return 0;
    book_draw();
    return 0;
}

/* (V195) a click on the page: a row selects it (only the two rows drawn
   again), the selected one again within CLICK_COUNT frames (a double
   click) dials it as Return; a button is its key (Edit and Delete act on
   the selected entry) */
unsigned char o_book_click(void)
{
    unsigned char i = btn_at(), old = sel;
    if (i < 5)
        return o_book_key(bk[i]);
    i = row_at(BOOK);
    if (i >= BOOK)
        return 0;
    if (i == sel && dblClickCount) {
        dblClickCount = 0;
        return o_book_key(13);
    }
    dblClickCount = CLICK_COUNT;
    if (i != old) {
        sel = i;
        book_row(old);
        book_row(i);
    }
#ifdef TERM_TEST
    strcpy((char *)crow, "TERM BOOK SEL ");
    crow[14] = hexd[i];
    crow[15] = 0;
    LogText((char *)crow);
#endif
    return 0;
}

/* the chosen entry (o_book_key gave 2) into name and addr */
void o_book_entry(char *name, char *addr)
{
    strcpy(name, bname(sel));
    strcpy(addr, baddr(sel));
}


/* options/copy screen: the window's text on the clipboard (crow_len,
   resident, maps this overlay again after reading a row) */
void o_copy_screen(void)
{
    static const unsigned char cardset[4] = { SCRAP_NEWCARDSET, 9, 0, 0 };
    unsigned int len = 4;
    unsigned char r, last = 0, n, i, e;
    for (r = 0; r < ROWS; ++r)
        if (crow_len(r))
            last = r + 1;
    for (r = 0; r < last; ++r)
        len += crow_len(r) + 1;
    e = scrap_text_begin(len);
    if (!e)
        e = scrap_write(cardset, 4);
    for (r = 0; !e && r < last; ++r) {
        n = crow_len(r);
        for (i = 0; i < n; ++i)
            if (crow[i] < 32 || crow[i] > 126)
                crow[i] = '?';
        crow[n] = 13;
        e = scrap_write(crow, n + 1);
    }
    if (scrap_close() && !e)
        e = DOS_ERROR;
    LogText(e ? "TERM COPY FAILED" : "TERM COPIED");
}

/* the document Veranda Term was started with (GetFile with ST_LD_DATA:
   dataFileName, a .TEL file holding an address book line, "name|host:port"
   or "host:port"; Dex writes one for its Connect: DECISIONS V56): in the
   current folder, else in curDirName's (V48). 1 and its name and address
   if there is one */
unsigned char o_doc(char *name, char *addr)
{
    unsigned char h, i = 0, f = 0, c;
    unsigned int len, k;
    h = FOpen((void *)dataFileName, 'r');
    if ((h < 2 || h > 9) && curDirName[0] == '/' && !ChDir((void *)curDirName))
        h = FOpen((void *)dataFileName, 'r');
    if (h < 2 || h > 9)
        return 0;
    len = FRead(h, rxbuf, 80);
    FClose(h);
    name[0] = addr[0] = 0;
    for (k = 0; k < len; ++k) {
        c = rxbuf[k];
        if (c == '\n' || c == '\r')
            break;
        if (c == '|' && !f) {
            f = 1;
            i = 0;
        } else if (!f && i < 24) {
            name[i++] = c;
            name[i] = 0;
        } else if (f && i < 40) {
            addr[i++] = c;
            addr[i] = 0;
        }
    }
    if (!f)                             /* "host:port" alone */
        strcpy(addr, name);
    return addr[0] != 0;
}
