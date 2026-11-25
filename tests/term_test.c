/* gate term: Veranda Term's test build (included at the end of term.c
   with TERM_TEST; tests/term_play.s plays the mouse and the keys).

   TERM.TST, one line: "<session> <stop> <baud index> <time zone>", e.g.
   "bbs end 4 4". Sessions (tools/gate_term.sh, tests/term_bbs.py):
     page    the script back-end: TERM.IN played at the baud rate, captured
             to CAPPAGE.TXT; the model at the end in TERM.SCR; stop
             settings or addr (V149): that page shown at the end
     bbs     dial "bbs.test:23" through the menu and the dial dialog; the
             ANSI page; "hello veranda" typed and echoed; file/about over
             the coloured screen; stop: menu (a menu open), dlg (the box
             open), back (PgUp: the scrollback), end
     speed   capture to SPEED.TXT, dial speed.test:23, until NO CARRIER;
             stop "aside" (V91): after 500 bytes TaskCtl(TASK_ASIDE): the
             kernel calls asideVector (the port's interrupts off, "TERM
             ASIDE"), the test desktop (tests/term_desk.s) waits 3 s while
             the BBS sends and brings Term back ("TERM BACK")
     xmodem  dial files.test:23, two downloads (DL1.BIN, DL2.BIN)
     clock   connect/clock from network, the box's YES clicked
     dex     started by Dex's Connect with DEX.TEL (gate da): it dials the
             document's host; the end once online (or 2 s without a UART)
     idle    (V194, gate term_tcp) the modem found, then 10 s with nothing
             happening: the status bar's draws (whole, in part), the
             cursor's and the bytes sent in them logged ("TERM IDLE");
             then Capture on (the status changes: drawn in part); the end
     mouse   (V195, gate term_tcp) the pages with the mouse: stop h the
             Hosts page, the 2nd and 3rd rows clicked; d those, then a
             double click on the 3rd (it connects); a the address book,
             row 9 clicked; b a double click on row 9 (it dials); e row 8
             clicked, then the Dial button
   The end: TERM.SCR written, a line logged, VRAM dumped. */

void __fastcall__ term_play(const unsigned int *script);
void term_dump(void);

static unsigned int scr[3 * 36];
static unsigned char ns;
static char tst[32];
static unsigned char tstep, tstop;
static unsigned int tt, tidle, tbase;
static unsigned long tlast;
static unsigned int tfirst, tend;
#ifndef TERM_UI
static unsigned long tbytes;
#endif

#define F_BTN 0x100
#define F_KEY 0x8000
#define F_END 0x2000
#define F_WAIT 0x1000

static void S(unsigned int f, unsigned int x, unsigned int y, unsigned int fl)
{
    scr[ns++] = f;
    scr[ns++] = x;
    scr[ns++] = (y & 255) | (y > 255 ? 0x4000 : 0) | fl;
}


/* a click (down, up 4 frames later) */
static void C(unsigned int f, unsigned int x, unsigned int y)
{
    S(f, x, y, 0);
    S(f + 3, x, y, F_BTN);
    S(f + 7, x, y, 0);
}

/* a menu of the bar (x) opened, its item n chosen (ix: inside the sub
   menu): the pointer goes into the sub menu at once, as a hand does
   (outside it the menu closes) */
static void M(unsigned int f, unsigned int x, unsigned int ix, unsigned char n)
{
    S(f, x, 7, 0);
    S(f + 1, x, 7, F_BTN);
    S(f + 2, ix, 24, 0);
    C(f + 20, ix, 24 + 16 * n);         /* (the Veranda look's lists: 16 lines an item, V74) */
}

#ifndef TERM_UI
static unsigned int typed(unsigned int f, const char *s)
{
    while (*s) {
        S(f, *s++, 0, F_KEY);
        f += 3;
    }
    return f;
}
#endif

static void go(void)
{
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0;
    term_play(scr);
    ns = 0;
}

static void snap(void)
{
    unsigned char h, r;
    h = FOpen("TERM.SCR", 'w');
    for (r = 0; r < ROWS; ++r) {
        vt_cell_text(r, rxbuf);
        vt_cell_attr(r, rxbuf + COLS);
        FWrite(h, rxbuf, 2 * COLS);
    }
    rxbuf[0] = vt_cx;
    rxbuf[1] = vt_cy;
    rxbuf[2] = tn_seen;
    rxbuf[3] = tn_on;
    rxbuf[4] = tn_echo;
    FWrite(h, rxbuf, 5);
    FClose(h);
}

static char *word(char *p, char *out)
{
    while (*p == ' ')
        ++p;
    while (*p > ' ')
        *out++ = *p++;
    *out = 0;
    return p;
}

static char sess[8], stopw[8], nb[4], tport[6];
#ifndef TERM_UI
static unsigned char tsent;
#endif

static void test_start(void)
{
    unsigned char h = FOpen("TERM.TST", 'r');
    char *p;
    if (h < 2)
        return;
    tst[FRead(h, tst, sizeof tst - 1)] = 0;
    FClose(h);
    p = word(word(tst, sess), stopw);
    p = word(p, nb);
    if (nb[0])
        cfg.baud = nb[0] - '0';
    p = word(p, nb);
    if (nb[0])
        cfg.tz = nb[0] - '0';
    word(p, tport);                     /* (net: the test server's port) */
    cfg.backend = sess[0] == 'p';
    tstop = stopw[0];
    if (sess[0] == 's' && tstop == 'a')
        cfg.uirq = 1;                   /* (V94: I off by default; "aside" keeps
                                           V91's case, the UART's interrupt on) */
    tstep = 1;
    tbase = ser_frames;
}

static char logl[64];

static void logn(const char *k, unsigned int v)
{
    char *p = put_str(logl, k);
    put_num(p, v)[0] = 0;
    LogText(logl);
}

static void the_end(void)
{
    capture_stop();
    snap();
#ifdef TERM_CLIP
    copy_screen();                      /* (gate clip: options/copy screen) */
#endif
    logn("TERM LOST ", ser_lost);
    logn("TERM OE ", ser_oe);
    logn("TERM TN ", tn_seen);
    logn("TERM ST FULL ", st_draws);    /* (V194) */
    logn("TERM ST PARTS ", st_parts);
    LogText("TERM END");
    term_dump();
}

/* a byte came in during the last frames? */
static unsigned char quiet(unsigned int n)
{
    if (rx_total != tlast) {
        if (!tfirst)
            tfirst = ser_frames;
        tend = ser_frames;
        tlast = rx_total;
        tidle = ser_frames;
    }
    return ser_frames - tidle > n && rx_total;
}

#ifndef TERM_UI                 /* (the full test build: every session but idle and mouse) */
/* (V112) the TCP sessions: net <stop> <baud> <tz> <port> (gate term_tcp) */
static void test_net(unsigned char q)
{
    if (tstep == 1 && tt >= 20) {
        if (tstop != 'n') {
            typed(0, "ATI\r");      /* (the serial terminal: the modem answers) */
            go();
        }
        tstep = 2;
    } else if (tstep == 2 && (q || tstop == 'n')) {
        unsigned int f;
        capture_start("CAPTCP.BIN");
        M(0, barx[2], mconn.left + 12, 0);  /* Connection > Connect... */
        if (tstop == 'f' || tstop == 'h')   /* (h: the page shown) */
            f = typed(60, tstop == 'f' ? "6\r" : "");  /* (the entry the raw session added) */
        else {
            f = typed(60, tstop == 'r' ? "N" : "C");
            if (tstop == 'r')
                f = typed(f + 30, "Echo\r");
            f = typed(typed(typed(f + 30, "127.0.0.1\r") + 30, "\b\b"), tport);
            f = typed(typed(f, "\r") + 30, tstop == 'r' ? "\bR\r\r" : "\r");   /* (r: added, then Return connects) */
        }
        if (tstop < 'r') {          /* f, h, n */
            S(f, (unsigned int)(tstop == 'h' ? &tstep : &test_box), 0, F_WAIT);       /* the box */
            S(30, 0, 0, F_END);
        }
        go();
        rx_total = 0;                /* (q: after the host's first byte) */
        tstep = 3;
    } else if (tstep == 3 && online && q) {
        snap();                     /* (the host's page) */
        tstep = 4;
    } else if (tstep == 4) {            /* 0-255 to the host, as typed bytes go */
        while (tx_room() >= 2) {
            net_send(tsent);
            if (!++tsent) {
                tidle = ser_frames;
                tstep = 5;
                break;
            }
        }
    } else if (tstep == 5 && q) {
        capture_stop();
        xm_start("DLT.BIN");
        tstep = 6;
    } else if (tstep == 6 && xm_result) {
        logn("TERM XM ", xm_result * 1000 + xm_crc * 100 + xm_big * 10);
        if (tstop == 't') {
            S(0, (unsigned int)&test_box, 0, F_WAIT);       /* closed by the host */
            S(30, 0, 0, F_END);
            go();
        } else
            net_hangup();           /* Disconnect */
        tstep = 7;
    } else if (tstep == 7 && !tcp) {
        typed(30, "ATI\r");         /* (the serial terminal again) */
        go();
        tidle = ser_frames;
        tstep = 8;
    } else if (tstep == 8 && q)
        the_end();
}

#else                           /* (TERM_UI: gate term_tcp's second test build, idle and mouse) */
/* (V194) idle: nothing drawn, nothing sent */
static unsigned int i_st, i_pt, i_cu;
static unsigned char i_tx;

static void idle_log(const char *k)
{
    char *p = put_str(logl, k);
    p = put_num(put_str(p, " STATUS "), st_draws - i_st);
    p = put_num(put_str(p, " PARTS "), st_parts - i_pt);
    p = put_num(put_str(p, " CURSOR "), vt_curdraws - i_cu);
    put_num(put_str(p, " TX "), (unsigned char)(ser_txhead - i_tx))[0] = 0;
    LogText(logl);
}

static void test_idle(void)
{
    if (tstep == 1 && !syncing && tt >= 120) {
        i_st = st_draws;
        i_pt = st_parts;
        i_cu = vt_curdraws;
        i_tx = ser_txhead;
        tbase = ser_frames;
        tstep = 2;
    } else if (tstep == 2 && tt >= 600) {
        idle_log("TERM IDLE 10S");
        i_st = st_draws;
        i_pt = st_parts;
        i_cu = vt_curdraws;
        capture_start("IDLE.TXT");      /* (the status: Capture added) */
        idle_log("TERM IDLE CAPTURE");
        tbase = ser_frames;
        tstep = 3;
    } else if (tstep == 3 && tt >= 60)
        the_end();
}

/* (V195) the pages with the mouse: rows at LISTTOP + 16 i */
#define ROWY(i) (LISTTOP + 16 * (i) + 8)

static void test_mouse(void)
{
    unsigned char h = tstop == 'h' || tstop == 'd';
    if (tstep != 1 || syncing || tt < 60)
        return;
    M(0, barx[2], mconn.left + 12, h ? 0 : 2);     /* Connect... or Address book */
    if (h) {
        C(60, 300, ROWY(1));            /* the 2nd host */
        C(90, 300, ROWY(2));            /* the 3rd */
        if (tstop == 'd') {
            C(110, 300, ROWY(2));       /* again, 20 frames later: a double click */
            S(30, (unsigned int)&test_box, 0, F_WAIT);  /* the box (refused) */
            S(30, 0, 0, F_END);
        } else
            S(150, 0, 0, F_END);
    } else if (tstop == 'a') {
        C(60, 300, ROWY(9));
        S(120, 0, 0, F_END);
    } else if (tstop == 'b') {
        C(60, 300, ROWY(9));
        C(80, 300, ROWY(9));            /* a double click: dial */
        S(400, 0, 0, F_END);
    } else {
        C(60, 300, ROWY(8));
        C(90, 8 + BTNW * 4, BTNY + 8);  /* Dial */
        S(400, 0, 0, F_END);
    }
    go();
    tstep = 2;
}
#endif

static void test_tick(void)
{
    unsigned char q;
    if (!tstep)
        return;
    tt = ser_frames - tbase;
    q = quiet(120);
    switch (sess[0]) {
#ifndef TERM_UI
    case 'd':                           /* Dex's Connect (gate da): dialled from DEX.TEL */
        if ((online && q) || (nouart && tt >= 120))
            the_end();
        break;
    case 'p':                           /* the script back-end */
        if (tstep == 1) {
            capture_start("CAPPAGE.TXT");
            dial("page", "page");
            tstep = 2;
        } else if (tstep == 2 && !ser_send && q) {
            if (tstop == 's' || tstop == 'a')   /* (V149: stop settings, addr: */
                page_open(tstop == 's' ? 1 : 2);        /* that page shown) */
            the_end();
        }
        break;
    case 'b':                           /* the BBS */
        if (tstep == 1 && tt >= 20) {
            M(0, barx[2], mconn.left + 12, 1);  /* Connection > Dial... */
            if (tstop == 'y')
                S(75, 0, 0, F_END);
            typed(typed(80, "bbs.test:23"), "\r");
            go();
            tstep = 2;
        } else if (tstep == 2 && online && q) {
            typed(typed(0, "hello veranda"), "\r");
            go();
            tidle = ser_frames;
            tstep = 3;
        } else if (tstep == 3 && q) {
            snap();                     /* (the screen before the menu) */
            if (tstop == 'm') {
                S(0, barx[0], 7, 0);    /* Term, open */
                S(1, barx[0], 7, F_BTN);
                S(2, mterm.left + 12, 24, 0);
                S(40, 0, 0, F_END);
            } else
                M(0, barx[0], mterm.left + 12, 0);      /* Term/about */
            if (tstop == 'd')
                S(100, 0, 0, F_END);
            S(100, 13, 0, F_KEY);       /* Return: OK */
            go();
            tbase = ser_frames;
            tstep = 4;
        } else if (tstep == 4 && tt > 200) {
            snap();
            if (tstop == 'b') {
                S(0, 0x82, 0, F_KEY);   /* PgUp */
                S(60, 0, 0, F_END);
                go();
                tstep = 5;
            } else
                the_end();
        }
        break;
    case 's':                           /* throughput and capture */
        if (tstep == 1) {
            if (tstop != 'a')           /* (a stream open: it would be asked to quit) */
                capture_start("SPEED.TXT");
            dial("speed", "speed.test:23");
            tstep = 2;
        } else if (tstep == 2 && online) {
            tstep = 3;                  /* from CONNECT on: the data */
            tfirst = 0;
            tbytes = rx_total;
        } else if (tstep == 3 && tstop == 'a' && rx_total > 500) {
            tstop = 0;                  /* (stop "aside", V91) */
            TaskCtl(TASK_ASIDE, 0, 0);
        } else if (tstep == 3 && !online && q) {
            logn("TERM BYTES ", rx_total - tbytes);
            logn("TERM FRAMES ", tend - tfirst);
            logn("TERM POLLS ", ser_polls);
            the_end();
        }
        break;
    case 'x':                           /* XMODEM */
        if (tstep == 1) {
            dial("files", "files.test:23");
            tstep = 2;
        } else if (tstep == 2 && online && q) {
            xm_start("DL1.BIN");
            tstep = 3;
        } else if (tstep == 3 && xm_result) {
            logn("TERM XM1 ", xm_result * 1000 + xm_crc * 100 + xm_big * 10);
            logn("TERM XM1 RETRIES ", xm_retries);
            xm_start("DL2.BIN");
            tstep = 4;
        } else if (tstep == 4 && xm_result) {
            logn("TERM XM2 ", xm_result * 1000 + xm_crc * 100 + xm_big * 10);
            logn("TERM XM2 RETRIES ", xm_retries);
            tstep = 5;
        } else if (tstep == 5 && !online && q)
            the_end();
        break;
    case 'n':                           /* (V112) TCP through the modem's command mode */
        test_net(q);
        break;
    case 'c':                           /* the clock */
        if (tstep == 1 && tt >= 20) {
            M(0, barx[2], mconn.left + 12, 5);  /* Connection > Clock from network */
            S(40, (unsigned int)&test_box, 0, F_WAIT);  /* the box is open */
            if (tstop == 'd')
                S(30, 0, 0, F_END);
            C(30, 256, 272);            /* YES */
            C(200, 256, 272);           /* (again: nothing there now: V40) */
            C(260, 100, 300);           /* (and in the window) */
            go();
            tstep = 2;
            tbase = ser_frames;
        } else if (tstep == 2 && test_boxed) {
            tbase = ser_frames;         /* the box was answered */
            tstep = 4;
        } else if (tstep == 4 && tt > 400) {
            /* Veranda's variables, then the ROM's clock (the RTC) */
            char *p = put_str(logl, "TERM VARS ");
            MAPBANK(ovl2);
            p = o_fmt_when(p, year, month, day, hour, minutes, seconds);
            LogText(logl);
            asm("jsr $FF50");           /* clock_get_date_time: r0-r3 */
            p = put_str(logl, "TERM RTC ");
            MAPBANK(ovl2);
            o_fmt_when(p, r0L, r0H, r1L, r1H, r2L, r2H);
            LogText(logl);
            the_end();
        }
        break;
#else
    case 'i':
        test_idle();
        break;
    case 'm':
        test_mouse();
        break;
#endif
    }
}
