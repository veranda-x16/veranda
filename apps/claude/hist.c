/* Veranda Claude and Veranda Ask: the chat history (a bank of its own:
   overlay 8 in Claude, 9 in Ask; DECISIONS V123).

   Every turn that ends saves the conversation to /DOCUMENTS/Chats/Claude
   (or .../Ask), made when missing: one file a chat, "0007 Title.chat"
   (the number counts up; the title is the first question's first 40
   characters, letters, digits and spaces). Written as CHAT.TMP, the old
   file deleted, CHAT.TMP renamed (as ASK.CFG is). The format (version 2,
   V143: the font's bytes, Veranda's set ISO-8859-16 and the private box
   glyphs; version 1, before it, CP437, still read: its letters made the
   set's; CR LF):

       VERANDA CHAT 2
       app=Claude                 (or Ask)
       title=Hello Claude
       model=claude-opus-5-5
       created=2026-11-21 08:00   (the X16's clock)
       updated=2026-11-21 08:05
       file=GAME.PRG              (the file attached last: Save back)
       (an empty line)
       u 11                       a message: its kind, its length in bytes,
       hello there                then its text and CR LF
       a 25
       ...
       end

   The kinds are the store's: u the user's, a the reply, n a note, x and
   y a turn left out, s a compaction's summary (sent as the user's), c
   and d compacted (shown, not sent). No key, token or password is ever
   written here.

   The Chats page (pg_on 3): the 16 newest chats (title, date, size),
   Open, Rename, Delete (asked first), New, Close. A chat opened goes
   into the store (too big: its newest part, from a user's message, and
   a note says how much was left out); its next turn is sent as any other
   (Remember, Compact: a saved summary is sent with the turns after it).
   A file that is not a chat, damaged or of a newer version is refused
   (a box), the conversation shown is kept. No file stays open across
   the main loop (Alt+Tab).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include "claude.h"
#ifdef ASK
#pragma code-name ("OVERLAY9")
#pragma rodata-name ("OVL9RO")
#pragma bss-name ("OVL9BSS")
#pragma data-name ("OVL9DATA")
#define APPDIR "Ask"
#else
#pragma code-name ("OVERLAY8")
#pragma rodata-name ("OVL8RO")
#pragma bss-name ("OVL8BSS")
#pragma data-name ("OVL8DATA")
#define APPDIR "Claude"
#endif

static const char magic[] = "VERANDA CHAT ";
#define VERSION '2'
/* (V143) version 1's CP437 $80-$FF: their bytes in the font (what it
   lacks folded or '?'; made by Python from the two sets) */
static const unsigned char cp1[128] = {
    0xC7, 0xFC, 0xE9, 0xE2, 0xE4, 0xE0, 0x61, 0xE7, 0xEA, 0xEB, 0xE8, 0xEF, 0xEE, 0xEC, 0xC4, 0x41,
    0xC9, 0xE6, 0xC6, 0xF4, 0xF6, 0xF2, 0xFB, 0xF9, 0xFF, 0xD6, 0xDC, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F,
    0xE1, 0xED, 0xF3, 0xFA, 0x6E, 0x4E, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0xAB, 0xBB,
    0x83, 0x84, 0x85, 0x86, 0x87, 0x3F, 0x3F, 0x3F, 0x3F, 0x9D, 0x96, 0x99, 0x9B, 0x3F, 0x3F, 0x88,
    0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x3F, 0x3F, 0x9A, 0x98, 0x9F, 0x9E, 0x9C, 0x97, 0x3F, 0x3F,
    0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x8F, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95,
    0x3F, 0xDF, 0x3F, 0x80, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F, 0x3F,
    0x3F, 0xB1, 0x3F, 0x3F, 0x3F, 0x3F, 0x2F, 0x3F, 0xB0, 0x3F, 0xB7, 0x82, 0x3F, 0x3F, 0x81, 0xA0
};
static unsigned char v1;
static const char tmp[] = "CHAT.TMP";

/* /DOCUMENTS/Chats/<the program's>, made when missing; 0: not there */
static unsigned char __fastcall__ in_dir(const char *d)
{
    strcpy(gph, d);
    if (ChDir(gph)) {
        MkDir(gph);
        if (ChDir(gph))
            return 0;
    }
    return 1;
}

static unsigned char h_cd(void)
{
    vr_cd(VR_DOCS);
    return in_dir("Chats") && in_dir(APPDIR);
}

/* the clock as "2026-11-21 08:05" */
static void __fastcall__ now_s(char *p)
{
    unsigned char v[5], i;
    v[0] = year;
    v[1] = month;
    v[2] = day;
    v[3] = hour;
    v[4] = minutes;
    p[0] = '2';
    p[1] = '0';
    for (i = 0; i < 5; ++i) {
        p[2 + i * 3] = '0' + v[i] / 10 % 10;
        p[3 + i * 3] = '0' + v[i] % 10;
        p[4 + i * 3] = i < 2 ? '-' : i == 2 ? ' ' : ':';
    }
    p[16] = 0;
}

/*---------------------------------------------------------------- writing */

static unsigned char wh, wbad;

/* n bytes of s (any bank but the store's) to the file, through dtext */
static void __fastcall__ w(const char *s, unsigned int n)
{
    unsigned char k;
    while (n) {
        k = n > 200 ? 200 : n;
        memcpy(dtext, s, k);
        wbad |= FWrite(wh, dtext, k) != 0;
        s += k;
        n -= k;
    }
}

static void __fastcall__ wl(const char *k, const char *v)
{
    w(k, strlen(k));
    w(v, strlen(v));
    w("\r\n", 2);
}

/* the first user message's text as a title (letters, digits, spaces; 40 at most) */
static void title(void)
{
    unsigned int a, nx;
    unsigned char i, n = 0, c, sp = 0;
    h_title[0] = 0;
    for (a = 0; a < st_used; a = nx) {
        nx = st_msg(a);
        if (st_k == K_USER || st_k == K_CUSER) {
            st_copy(a + 3, line, st_n > 60 ? 60 : st_n);
            for (i = 0; i < 60 && i < st_n && n < 40; ++i) {
                c = line[i];
                if ((c >= '0' && c <= '9') || ((c | 32) >= 'a' && (c | 32) <= 'z')) {
                    if (sp && n)
                        h_title[n++] = ' ';
                    h_title[n++] = c;
                    sp = 0;
                } else
                    sp = 1;
            }
            break;
        }
    }
    h_title[n] = 0;
    if (!n)
        strcpy(h_title, "Chat");
}

/* the name "0007 Title.chat" (gph) */
static void __fastcall__ name_of(unsigned int seq, const char *t)
{
    unsigned char i;
    for (i = 4; i--; seq /= 10)
        gph[i] = '0' + seq % 10;
    gph[4] = ' ';
    strcpy(gph + 5, t);
    strcat(gph, ".chat");
}

/*---------------------------------------------------------------- the folder's chats */

#define HMAX 16
struct hent {
    unsigned int seq;
    char t[41];                 /* the title (from the name) */
    char date[17];
    unsigned long size;
};
static struct hent H[HMAX];
static unsigned char hn, hsel, htop;

static unsigned char __fastcall__ hexv(unsigned char c)
{
    return c <= '9' ? c - '0' : (c & 0x0F) + 9;
}

/* the folder's listing ("$=L": long names, sizes, dates) into H, the
   newest (the highest numbers) first; the highest number in htop */
static void list(void)
{
    char *q, *n;
    unsigned char i, l, first = 1;
    unsigned int seq;
    struct hent e;
    hn = htop = 0;
    strcpy(dtext, "=L");                /* (below $A000: the kernel reads it) */
    if (!h_cd() || DirOpen(dtext))
        return;
    rbuf[125] = 0;
    while (DirNext(rbuf) == 0) {
        if (first) {
            first = 0;
            continue;
        }
        q = strchr((char *)rbuf + 3, '"');
        if (!q)
            continue;
        n = ++q;
        if (!(q = strchr(q, '"')))
            continue;
        *q++ = 0;
        l = strlen(n);
        if (l < 11 || l > 50 || strcmp(n + l - 5, ".chat") || n[4] != ' ')
            continue;
        for (i = 0, seq = 0; i < 4; ++i) {
            if (n[i] < '0' || n[i] > '9')
                break;
            seq = seq * 10 + n[i] - '0';
        }
        if (i < 4)
            continue;
        if (seq > htop)
            htop = seq;
        memset(&e, 0, sizeof e);
        e.seq = seq;
        n[l - 5] = 0;
        strncpy(e.t, n + 5, 40);
        while (*q == ' ')
            ++q;
        if (*q)
            q += 3;
        while (*q == ' ' || *q == '<')
            ++q;
        if (q[4] == '-' && q[13] == ':') {
            memcpy(e.date, q, 16);
            q += 19;
            while (*q == ' ')
                ++q;
            if (q[0] && q[1] && q[2] == ' ')
                for (q += 3, i = 0; i < 8 && q[i] > ' '; ++i)
                    e.size = e.size << 4 | hexv(q[i]);
        }
        /* (in order: the highest number first) */
        for (i = hn; i && H[i - 1].seq < seq; --i)
            if (i < HMAX)
                H[i] = H[i - 1];
        if (i < HMAX) {
            H[i] = e;
            if (hn < HMAX)
                ++hn;
        }
    }
}

/*---------------------------------------------------------------- saving */

void h_save(void)
{
    unsigned int a, nx, k, i;
    unsigned char any = 0;
    char *p;
    for (a = 0; a < st_used; a = nx) {
        nx = st_msg(a);
        if (st_k == K_USER || st_k == K_CUSER)
            any = 1;
    }
    if (!any || !h_cd())
        return;
    if (!h_seq) {                       /* (a new chat: the next number, its title) */
        list();
        h_seq = htop + 1;
        title();
        now_s(h_created);
    }
    strcpy(gph, tmp);
    wh = FOpen(gph, 'w');
    if (wh < 2 || wh > 4)
        return;
    wbad = 0;
    strcpy(line, magic);
    p = line + strlen(line);
    *p++ = VERSION;
    *p = 0;
    wl(line, "");
    wl("app=", APPDIR);
    wl("title=", h_title);
#ifdef ASK
    wl("model=", C.mslug);
#else
    wl("model=", model_id[C.model]);
#endif
    wl("created=", h_created);
    now_s(line);
    wl("updated=", line);
    if (af_name[0])
        wl("file=", af_name);
    w("\r\n", 2);
    for (a = 0; a < st_used && a != st_cur; a = nx) {
        nx = st_msg(a);
        if (st_k == K_CINST || st_k == K_HIDDEN)
            continue;
        line[0] = st_k;
        line[1] = ' ';
        p = unum(line + 2, st_n);
        strcpy(p, "\r\n");
        w(line, strlen(line));
        for (i = 0; i < st_n; i += k) {
            k = st_n - i > 200 ? 200 : st_n - i;
            st_copy(a + 3 + i, dtext, k);
            wbad |= FWrite(wh, dtext, k) != 0;
        }
        w("\r\n", 2);
    }
    w("end\r\n", 5);
    wbad |= FClose(wh) != 0;
    if (wbad)
        return;
    name_of(h_seq, h_title);
    FDelete(gph);
    strcpy(line, tmp);
    FRename(line, gph);
#ifdef CLAUDE_TEST
    strcpy(line, "CL CHAT SAVED ");
    strcat(line, gph);
    gt_log(line);
#endif
}

/*---------------------------------------------------------------- opening */

static unsigned char rh, rn_, rp;
static unsigned char rbad;

static int rd(void)
{
    if (rp == rn_) {
        rn_ = FRead(rh, rbuf, 128);
        rp = 0;
        if (!rn_)
            return -1;
    }
    return rbuf[rp++];
}

/* a line (CR LF, or LF) into line (199 at most); 0: the file's end */
static unsigned char rline(void)
{
    int c;
    unsigned char n = 0;
    for (;;) {
        c = rd();
        if (c < 0)
            return n != 0;
        if (c == '\n')
            break;
        if (c != '\r' && n < 199)
            line[n++] = c;
    }
    line[n] = 0;
    return 1;
}

static const char kinds[] = "uanxysdc";

/* the chat H[hsel]: pass 1 checks it (0: refused, rbad why) and counts its
   messages' bytes (tot); pass 2 (into) puts the newest that fit in the store */
static unsigned long tot;
static unsigned int skip;
static unsigned char started;
#define LOADMAX ((unsigned long)STSIZE - 14336ul)      /* (the store less a reply's room and some) */

static unsigned char __fastcall__ pass(unsigned char into)
{
    unsigned int n, i, k;
    unsigned long done = 0;
    unsigned char kind, c;
    char *p;
    if (!h_cd())                        /* (it uses gph: the name after it) */
        return 0;
    name_of(H[hsel].seq, H[hsel].t);
    rh = FOpen(gph, 'r');
    if (rh < 2 || rh > 4 || dosStatus >= 20) {
        if (rh >= 2 && rh <= 4)
            FClose(rh);
        rbad = 1;
        return 0;
    }
    rn_ = rp = 0;
    rbad = 2;                           /* (damaged, unless it is all read) */
    if (!rline() || memcmp(line, magic, 13))
        goto out;
    if (line[13] > VERSION) {
        rbad = 3;                       /* (a newer version) */
        goto out;
    }
    v1 = line[13] == '1';
    while (rline() && line[0]) {
        if (into && !memcmp(line, "file=", 5))
            strncpy(af_name, line + 5, 63);
        if (into && !memcmp(line, "title=", 6))
            strncpy(h_title, line + 6, 40);
        if (into && !memcmp(line, "created=", 8))
            strncpy(h_created, line + 8, 16);
    }
    if (!into)
        tot = 0;
    skip = started = 0;
    for (;;) {
        if (!rline())
            goto out;
        if (!strcmp(line, "end"))
            break;
        kind = line[0];
        if (!strchr(kinds, kind) || line[1] != ' ')
            goto out;
        for (n = 0, p = line + 2; *p >= '0' && *p <= '9' && n < 6553; ++p)
            n = n * 10 + *p - '0';
        if (*p || n > 40000u)
            goto out;
        /* pass 2: the older messages left out while the rest does not fit
           (and until a user's message starts it) */
        if (into && !started && (tot - done > LOADMAX || (skip && kind != 'u' && kind != 's'))) {
            done += n + 3;
            ++skip;
            for (i = 0; i < n; ++i)
                if (rd() < 0)
                    goto out;
        } else if (into) {
            started = 1;
            if (!st_open(kind))
                goto out;
            for (i = 0; i < n; i += k) {
                k = n - i > 128 ? 128 : n - i;
                for (c = 0; c < k; ++c) {
                    int b = rd();
                    if (b < 0)
                        goto out;
                    if (v1 && b >= 0x80)
                        b = cp1[b - 0x80];
                    dtext[c] = b;
                }
                st_append(dtext, k);
            }
            st_close();
        } else {
            tot += n + 3;
            for (i = 0; i < n; ++i)
                if (rd() < 0)
                    goto out;
        }
        if (rd() != '\r' || rd() != '\n')
            goto out;
    }
    rbad = 0;
out:
    FClose(rh);
    return !rbad;
}

static void __fastcall__ h_open(void)
{
    char *p;
    if (!pass(0)) {
        message("This chat cannot be opened:", rbad == 3 ? "it is from a newer version of the program." :
                rbad == 1 ? "the file cannot be read." : "it is damaged (not a Veranda chat).");
#ifdef CLAUDE_TEST
        gt_log(rbad == 3 ? "CL CHAT REFUSED NEWER" : "CL CHAT REFUSED DAMAGED");
#endif
        return;
    }
    st_clear();
    p_in = p_out = p_cache = 0;
    ovv(c_newconv);                     /* (the blocks, the usage, the file attached) */
    af_name[0] = 0;
    pass(1);
    h_seq = H[hsel].seq;
    st_prot = st_used;
    strcpy(msg, "Opened: ");
    strncat(msg, h_title, 40);
    if (skip) {
        strcpy(line, "(The chat was too big for the memory: its ");
        p = unum(line + strlen(line), skip);
        strcpy(p, " oldest messages were left out here; the file keeps them.)");
        st_add(K_NOTE, line, strlen(line));
        strcat(msg, " (its newest part)");
    }
    pg_on = 0;
    c_ui |= CU_ALL | CU_STATUS;
#ifdef CLAUDE_TEST
    gt_log("CL CHAT OPENED");
#endif
}

/*---------------------------------------------------------------- the Chats page (pg_on 3) */

#define LY 72                           /* the rows */
#define BY 352                          /* the buttons */

static void __fastcall__ row(unsigned char i)
{
    char *p;
    unsigned int y = LY + i * 16;
    memset(line, ' ', 76);
    line[76] = 0;
    if (i < hn) {
        memcpy(line + 1, H[i].t, strlen(H[i].t));
        memcpy(line + 44, H[i].date, strlen(H[i].date));
        p = unum(line + 62, (H[i].size + 1023) / 1024);
        strcpy(p, " KB");
    }
    put(2, y + 4, line, 76, i == hsel && i < hn && !hl);
    theme_rect(2, 76, y >> 3, 2, i == hsel && i < hn && hl ? hl : 0);
}

static void draw(void)
{
    unsigned char i;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 48, 639, 463);
    theme_rect(0, 80, 6, 52, 0);
    heading("Chats", "/DOCUMENTS/Chats/" APPDIR ": saved after every turn");
    if (!hn)
        put(3, LY + 4, "No chats yet: each conversation is saved here after its first turn.", 76, 0);
    for (i = 0; i < HMAX; ++i)
        row(i);
    button(2, 8, BY, "Open", 0);
    button(11, 10, BY, "Rename", 0);
    button(22, 10, BY, "Delete", 0);
    button(33, 8, BY, "New", 0);
    button(42, 8, BY, "Close", 0);
    put(2, BY + 24, "Up, Down choose; Return opens; Delete deletes (asked); N new; Esc closes.", 78, 0);
}

void h_page(void)
{
    list();
    hsel = 0;
    pg_on = 3;
    draw();
#ifdef CLAUDE_TEST
    {
        char *p;
        strcpy(line, "CL CHATS ");
        p = unum(line + 9, hn);
        if (hn) {
            *p++ = ' ';
            strcpy(p, H[0].t);
        }
        gt_log(line);
    }
#endif
}

static void del(void)
{
    if (hsel >= hn || !yesno("Delete this chat?", H[hsel].t))
        return;
    if (h_cd()) {
        name_of(H[hsel].seq, H[hsel].t);
        FDelete(gph);
    }
    if (H[hsel].seq == h_seq)
        h_seq = 0;                      /* (the one shown: saved as a new one next time) */
    list();
    if (hsel >= hn && hsel)
        --hsel;
    draw();
}

static void ren(void)
{
    char *p;
    if (hsel >= hn)
        return;
    strcpy(line, H[hsel].t);
    if (!ask("The chat's new title:", line, 40) || !line[0])
        return;
    for (p = line; *p; ++p)             /* (a file name: no / : * ? " < > |) */
        if (strchr("/\\:*?\"<>|", *p) || *p < 32)
            *p = ' ';
    if (h_cd()) {
        name_of(H[hsel].seq, H[hsel].t);
        memcpy(dtext, gph, 64);
        name_of(H[hsel].seq, line);
        FRename(dtext, gph);
    }
    if (H[hsel].seq == h_seq) {         /* (the one shown: written again with its title) */
        strncpy(h_title, line, 40);
        h_save();
    }
    list();
    draw();
}

static void close_(void)
{
    pg_on = 0;
    c_ui |= CU_ALL;
}

void h_key(void)
{
    unsigned char k = keyData, o = hsel;
    if (keyDataMods & KEYM_ARROW) {
        if (k == KEY_UP && hsel)
            --hsel;
        else if (k == KEY_DOWN && hsel + 1 < hn)
            ++hsel;
        row(o);
        row(hsel);
        return;
    }
    switch (k) {
    case 13: h_open(); break;
    case KEY_ESC: close_(); break;
    case KEY_DELETE: del(); break;
    case 'n': case 'N': close_(); c_ui |= CU_NEW; break;
    }
}

void h_press(void)
{
    unsigned int y = mouseYPosW;
    unsigned char c = mouseXPos >> 3, o = hsel;
    if (y >= LY && y < LY + HMAX * 16) {
        hsel = (y - LY) >> 4;
        if (hsel >= hn)
            hsel = o;
        row(o);
        row(hsel);
        return;
    }
    if (y < BY || y >= BY + 14)
        return;
    if (c >= 2 && c < 10)
        h_open();
    else if (c >= 11 && c < 21)
        ren();
    else if (c >= 22 && c < 32)
        del();
    else if (c >= 33 && c < 41) {
        close_();
        c_ui |= CU_NEW;
    } else if (c >= 42 && c < 50)
        close_();
}
