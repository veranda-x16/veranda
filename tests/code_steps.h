/* gates claude and ask (DECISIONS V123): the code session, included by
   tests/claude_play.c and tests/ask_play.c (built with -DCODE_SESSION: the
   test's overlay has no room for it beside the other sessions).
   MIT licence (see LICENSE). */
#ifdef ASK
#define MI_CONV    1            /* Settings > Conversation... */
#define MI_COMPACT 2            /* Settings > Compact conversation */
/* rows from..to - 1: "CL ROW <flags> <text>" */
static void __fastcall__ rows_log(unsigned int from, unsigned int to)
{
    unsigned char fl, n;
    for (; from < to && from < st_rows; ++from) {
        fl = row_get(from);
        strcpy(tl, "CL ROW ");
        unum(tl + 7, fl);
        strcat(tl, " ");
        n = strlen(tl);
        memcpy(tl + n, cs_txt, TW);
        tl[n + TW] = 0;
        while (tl[n] && tl[strlen(tl) - 1] == ' ')
            tl[strlen(tl) - 1] = 0;
        LogText(tl);
    }
}
#else
#define MI_CONV    4
#define MI_COMPACT 5
#endif

/*---------------------------------------------------------------- V123: the code session

   code (tools/gate_claude.sh's): CLAUDE.CFG with a key; three plain turns
   (the bodies' prefixes); a reply with a BASIC and a Python block (its
   rows marked, the labels: code.png); Code > Copy last code block (the
   Python: SCRAP1.CVT), [Copy] on the BASIC (SCRAP2.CVT), Code > Copy last
   reply (SCRAP3.CVT), [Save .PRG] (PROGRAM.PRG) and [Save...]
   (PROGRAM.BAS) on the BASIC; the Conversation page: Remember the last
   4; two turns (the request's messages; the blocks saved and copied sent
   shortened); Remember all again; Code > Attach a file... GAME.PRG (a
   tokenized program from /DOCUMENTS): a question with it (attach.png);
   the reply's new version saved over GAME.PRG (replace: Yes); a turn
   (the old version shortened); Settings > Compact conversation (Haiku,
   the summary: compact.png); a turn after it; one to the cheap model
   (t_cheap, as Ctrl+Return sets it); short answers; a long reply, then
   compact when long: the automatic compaction before the question */

/* the scrap file copied to name (in the root): what the clipboard held then */
static void __fastcall__ scrap_keep(const char *name)
{
    unsigned char a, b;
    unsigned int n;
    strcpy(tl, VR_DATAPATH "Text  Scrap.cvt");
    a = FOpen(tl, 'r');
    if (a < 2 || a > 4 || dosStatus >= 20) {    /* (the library's other folder: the root) */
        if (a >= 2 && a <= 4)
            FClose(a);
        strcpy(tl, VR_ROOTPATH "Text  Scrap.cvt");
        a = FOpen(tl, 'r');
    }
    strcpy(tl, VR_ROOTPATH);
    strcat(tl, name);
    b = FOpen(tl, 'w');
    if (a >= 2 && a <= 4 && b >= 2 && b <= 4)
        while ((n = FRead(a, line, 128)) != 0) {
            FWrite(b, line, n);
            if (n < 128)
                break;
        }
    if (a >= 2 && a <= 4)
        FClose(a);
    if (b >= 2 && b <= 4)
        FClose(b);
    logs("CL TEST SCRAP ", name);
}

/* the k-th fence row (0: the first) shown: its pixel row's middle, 0: not shown */
static unsigned int __fastcall__ fence_y(unsigned char k)
{
    unsigned int i;
    for (i = 0; i < st_rows; ++i) {
        row_at(i);
        if ((row_fl & R_FENCE) && !k--)
            return i >= v_top && i < v_top + BROWS ? BODYY + (i - v_top) * RH + 8 : 0;
    }
    return 0;
}

/* the last fence row shown */
static unsigned int fence_last(void)
{
    unsigned int i, y = 0;
    for (i = 0; i < st_rows; ++i) {
        row_at(i);
        if ((row_fl & R_FENCE) && i >= v_top && i < v_top + BROWS)
            y = BODYY + (i - v_top) * RH + 8;
    }
    return y;
}

#define LBL(c) ((TX + (c)) * 8 + 4)     /* a label's column: its pixel x */

/* the blocks code.c found: "CL BLK a ca ce e lines flags name" */
static void blocks_log(void)
{
    unsigned char j;
    for (j = 0; j < nblk; ++j) {
        strcpy(tl, "CL BLK ");
        unum(tl + strlen(tl), B[j].a);
        strcat(tl, " ");
        unum(tl + strlen(tl), B[j].ca);
        strcat(tl, " ");
        unum(tl + strlen(tl), B[j].ce);
        strcat(tl, " ");
        unum(tl + strlen(tl), B[j].e);
        strcat(tl, " ");
        unum(tl + strlen(tl), B[j].lines);
        strcat(tl, " ");
        unum(tl + strlen(tl), B[j].fl);
        strcat(tl, " ");
        strcat(tl, B[j].name);
        LogText(tl);
    }
}

/* (V129) a second's wait after a step's end before the next is typed:
   a compaction's or a box's end may still be clearing the input box (the
   keys typed meanwhile went astray when the timing shifted) */
static unsigned int c_wait;

static unsigned char settled(void)
{
    if (!c_wait) {
        c_wait = ser_frames | 1;
        return 0;
    }
    if (ser_frames - c_wait < 60)
        return 0;
    c_wait = 0;
    return 1;
}

static void code_steps(void)
{
    unsigned int y;
    switch (step) {
    case 1:
        if (pg_on || net_state() != NET_READY || !idle())
            return;
        turn("plain one", 0);
        break;
    case 2:
        if (!turned())
            return;
        turn("plain two", 0);
        break;
    case 3:
        if (!turned())
            return;
        turn("plain three", 0);
        break;
    case 4:
        if (!turned())
            return;
        turn("code please", 0);
        break;
    case 5:                             /* the blocks: rows, labels; Code > Copy last code block */
        if (!turned())
            return;
        rows_log(st_rows > 24 ? st_rows - 24 : 0, st_rows);
        snap("CODE.RAW");
        M(10, 3, 0);
        go_();
        break;
    case 6:                             /* [Copy] on the BASIC */
        if (!idle())
            return;
        scrap_keep("SCRAP1.CVT");
        y = fence_y(0);
        logn("CL TEST FENCE Y ", y);
        CK(10, LBL(15), y);
        go_();
        break;
    case 7:                             /* Code > Copy last reply */
        if (!idle())
            return;
        scrap_keep("SCRAP2.CVT");
        M(10, 3, 3);
        go_();
        break;
    case 8:                             /* [Save .PRG]: the name as it is */
        if (!idle())
            return;
        scrap_keep("SCRAP3.CVT");
        CK(10, LBL(35), fence_y(0));
        Sx(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
        typed(30, "\r");
        go_();
        break;
    case 9:                             /* [Save...]: PROGRAM.BAS */
        if (!idle() || t_nbox == nbox)
            return;
        CK(10, LBL(24), fence_y(0));
        Sx(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
        typed(30, "\r");
        go_();
        break;
    case 10:                            /* Settings > Conversation...: Remember the last 4 */
        if (!idle() || t_nbox == nbox)
            return;
        M(10, 2, MI_CONV);
        Sx(tlen + 10, (unsigned int)&pg_on, 0, 0x1000);
        typed(30, "11\r");
        go_();
        break;
    case 11:
        if (pg_on || !idle())
            return;
        logn("CL TEST REMEMBER ", C.rem);
        turn("plain four", 0);
        break;
    case 12:
        if (!turned())
            return;
        turn("plain five", 0);
        break;
    case 13:                            /* Remember everything again */
        if (!turned())
            return;
        snap("SHORT.RAW");
        M(10, 2, MI_CONV);
        Sx(tlen + 10, (unsigned int)&pg_on, 0, 0x1000);
        typed(30, "11\r");
        go_();
        break;
    case 14:                            /* Code > Attach a file...: GAME.PRG */
        if (pg_on || !idle())
            return;
        logn("CL TEST REMEMBER ", C.rem);
        M(10, 3, 4);
        Sx(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
        typed(30, "GAME.PRG\r");
        go_();
        break;
    case 15:
        if (!idle() || t_nbox == nbox || !settled())
            return;
        logn("CL TEST ATTACHED ", att_on);
        logs("CL TEST ATTLBL ", att_lbl);
        snap("ATTACH.RAW");
        turn("fix please: line 30 says X+", 0);
        break;
    case 16:                            /* its new version saved over the file: [Save...], Return, Yes */
        if (!turned())
            return;
        msgs_log();
        y = fence_last();
        logn("CL TEST FENCE Y ", y);
        CK(10, LBL(24), y);
        Sx(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
        typed(30, "\r");
        box_ok(40);
        go_();
        break;
    case 17:
        if (!idle() || t_nbox < nbox + 2)
            return;
        blocks_log();
        turn("plain six", 0);
        break;
    case 18:                            /* Settings > Compact conversation */
        if (!turned())
            return;
        blocks_log();
        M(10, 2, MI_COMPACT);
        go_();
        ++want;
        break;
    case 19:
        if (!turned() || !settled())
            return;
        msgs_log();
        snap("COMPACT.RAW");
        turn("plain after", 0);
        break;
    case 20:                            /* the cheap model (Ctrl+Return's t_cheap) */
        if (!turned())
            return;
        t_cheap = 1;
        turn("cheap please", 0);
        break;
    case 21:
        if (!turned())
            return;
        t_cheap = 0;
        break;
    case 22:                            /* short answers */
        if (!turned())
            return;
        M(10, 2, MI_CONV);
        Sx(tlen + 10, (unsigned int)&pg_on, 0, 0x1000);
        typed(30, "2\r");
        go_();
        break;
    case 23:
        if (pg_on || !idle() || ser_frames - tstep_t < 120)
            return;                     /* (the page's settings written first: no keys lost meanwhile) */
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("short please", 0);
        break;
    case 24:                            /* short answers off; a big reply, a turn after it (the hint) */
        if (!turned())
            return;
        M(10, 2, MI_CONV);
        Sx(tlen + 10, (unsigned int)&pg_on, 0, 0x1000);
        typed(30, "2\r");
        go_();
        break;
    case 25:
        if (pg_on || !idle() || ser_frames - tstep_t < 120)
            return;                     /* (the page's settings written first: no keys lost meanwhile) */
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("big please", 0);
        break;
    case 26:
        if (!turned())
            return;
        turn("plain long", 0);
        break;
    case 27:                            /* compact when long: the question compacted first, then sent */
        if (!turned())
            return;
        M(10, 2, MI_CONV);
        Sx(tlen + 10, (unsigned int)&pg_on, 0, 0x1000);
        typed(30, "4\r");
        go_();
        break;
    case 28:
        if (pg_on || !idle() || ser_frames - tstep_t < 120)
            return;                     /* (the page's settings written first: no keys lost meanwhile) */
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("plain auto", 0);
        ++want;
        break;
    case 29:
        if (!turned())
            return;
        msgs_log();
        snap("FINAL.RAW");
        the_end();
        return;
    }
    NEXT();
}


/*---------------------------------------------------------------- the chats (V123)

   hist1 ("h"): two turns (the chat saved after each); hist2 ("2": the
   program started again in the same folder, with a damaged chat and one
   of a newer version put there by the gate): File > Chats...
   (chats.png), the newer one refused, the damaged one refused, the first
   one opened (its messages), a third turn (its request has the history),
   Rename, Delete (Yes), Esc */
#define ROWY(i) (72 + (i) * 16 + 8)
#define BTNX(c) ((c) * 8 + 12)
#define BTNYY   (352 + 7)

static void hist_steps(void)
{
    unsigned int f;
    unsigned char i;
    switch (step) {
    case 1:
        if (pg_on || net_state() != NET_READY || !idle())
            return;
        if (sess == '2') {              /* (hist2) File > Chats... */
            M(10, 1, 1);
            go_();
            break;
        }
        turn("plain one", 0);
        break;
    case 2:
        if (sess == '2') {              /* the newest: a newer version: refused */
            if (pg_on != 3 || !idle())
                return;
            snap("CHATS.RAW");
            typed(10, "\r");
            box_ok(20);
            go_();
            break;
        }
        if (!turned())
            return;
        turn("plain two", 0);
        break;
    case 3:
        if (sess != '2') {
            if (!turned())
                return;
            msgs_log();
            the_end();
            return;
        }
        if (!idle() || t_nbox == nbox)  /* the damaged one: refused */
            return;
        CK(10, 200, ROWY(1));
        CK(30, BTNX(2), BTNYY);
        box_ok(50);
        go_();
        break;
    case 4:                             /* the first chat opened */
        if (!idle() || t_nbox == nbox)
            return;
        CK(10, 200, ROWY(2));
        CK(30, BTNX(2), BTNYY);
        go_();
        break;
    case 5:
        if (pg_on || !idle())
            return;
        msgs_log();
        snap("OPENED.RAW");
        turn("plain three", 0);
        break;
    case 6:                             /* Rename the chat */
        if (!turned())
            return;
        M(10, 1, 1);
        Sx(tlen + 10, (unsigned int)&pg_on, 0, 0x1000);
        CK(30, 200, ROWY(2));
        CK(50, BTNX(11), BTNYY);
        Sx(70, (unsigned int)&t_box, 0, 0x1000);
        for (f = 90, i = 0; i < 12; ++i, f += 3)
            Sx(f, 8, 0, F_KEY);
        typed(f, "renamed chat\r");
        go_();
        break;
    case 7:                             /* Delete the damaged one: Yes */
        if (!idle() || t_nbox == nbox)
            return;
        CK(10, 200, ROWY(1));
        CK(30, BTNX(22), BTNYY);
        box_ok(50);
        go_();
        break;
    case 8:
        if (!idle() || t_nbox == nbox)
            return;
        typed(10, "\x1b");
        go_();
        break;
    case 9:
        if (pg_on || !idle())
            return;
        the_end();
        return;
    }
    NEXT();
}
