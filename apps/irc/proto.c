/* Veranda Chat: IRC (overlay 2; DECISIONS V111).

   A line from the server (RFC 1459, RFC 2812; IRCv3 tags skipped):
   [@tags] [:prefix] command params [:trailing], handled:
     registration  PASS, NICK, USER sent at the connection; 433 (and 432,
                   436) before 001: the alternative nick, then the nick
                   with "_" added; 001: registered, the server's channels
                   joined (one JOIN, by commas)
     PING          PONG with its token, at once
     numerics      the welcome, the MOTD (375, 372, 376) and the rest in
                   the server's window; 332 the topic, 353 and 366 the
                   names (the list made again); 4xx and 5xx errors in the
                   window shown
     JOIN, PART, QUIT, NICK, KICK, MODE (+o, +v, +h ... the nick list),
     TOPIC, INVITE, NOTICE, PRIVMSG (to a channel: its window; to us:
                   a query window, opened for it), ERROR (the reason)
     CTCP          ACTION shown as "* nick text"; VERSION and PING
                   answered (NOTICE); others noted
   Every text shown is cleaned: IRC's formatting codes (bold, colours,
   italics ...) taken out, UTF-8 decoded into Veranda's set, ISO-8859-16
   (V140, V143: the SDK's vrcs.h; what the set lacks folded: Latin
   Extended-A to its base letters, quotes and dashes to ASCII, combining
   marks dropped, the rest '?'), a byte that is not UTF-8 taken as
   Latin-1. Our nick in a channel's
   message is a mention: the line marked, the system's sound.

   (V178) A channel's people are counted apart from the nicks kept
   (store.c keeps NMAX): every name of NAMES, then JOIN, PART, KICK, and
   QUIT for a nick in the list (a QUIT names no channel: one of those not
   kept is not known to be in it). Every line made here is cut to its
   buffer (hd, obuf), whatever the server sends.

   The input line's commands are input.c's (overlay 4).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "chat.h"
#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")

static char *pfx, *cmd, *par[15];
static unsigned char np;
static char from[NAMEMAX];              /* (main RAM: store.c reads it) */
static const char *uhost;
static unsigned char me_from;           /* the line is ours */

static const char *const version = "\001VERSION Veranda Chat 1.0 (Commander X16)\001";

/*---------------------------------------------------------------- the text cleaned */

static const char exta[128] =
    "AaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiIiJjKkkLlLlLlL"
    "lLlNnNnNnnNnOoOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZzs";

static char *dp, *dend;

static void __fastcall__ emit(unsigned char c)
{
    if (dp < dend)
        *dp++ = c;
}

static unsigned char __fastcall__ cont(const unsigned char *s, unsigned char n)
{
    while (n--)
        if ((*++s & 0xC0) != 0x80)
            return 0;
    return 1;
}

static unsigned char __fastcall__ isdig(unsigned char c)
{
    return c >= '0' && c <= '9';
}

static unsigned char __fastcall__ ishex(unsigned char c)
{
    return isdig(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static void __fastcall__ fold(unsigned int u)
{
    unsigned char c;
    if (u == 0xA0)
        emit(' ');
    else if ((c = l10_byte(u)) != 0)    /* (the set's, ASCII too: main.c) */
        emit(c);
    else if (u >= 0x100 && u < 0x180)
        emit(exta[u - 0x100]);
    else if (u >= 0x2010 && u <= 0x2015)
        emit('-');
    else if (u >= 0x2018 && u <= 0x201B)
        emit('\'');
    else if (u >= 0x201C && u <= 0x201F)
        emit('"');
    else if (u == 0x2022)
        emit(0xB7);
    else if (u == 0x2026) {
        emit('.');
        emit('.');
        emit('.');
    } else if ((u >= 0x300 && u < 0x370) || (u >= 0x200B && u <= 0x200F) || u == 0xFE0F || u == 0xFEFF)
        ;                               /* (combining marks, zero widths: nothing) */
    else
        emit('?');
}

/* s cleaned onto d (its end: max - 1 bytes from d at most); the end */
static char *__fastcall__ clean(char *d, const char *s, unsigned int max)
{
    const unsigned char *p = (const unsigned char *)s;
    unsigned char c, k;
    dp = d;
    dend = d + max - 1;
    while ((c = *p) != 0) {
        if (c < 32) {
            ++p;
            if (c == 3) {               /* a colour: ^Cff[,bb] */
                for (k = 0; k < 2 && isdig(*p); ++k)
                    ++p;
                if (k && *p == ',' && isdig(p[1])) {
                    ++p;
                    for (k = 0; k < 2 && isdig(*p); ++k)
                        ++p;
                }
            } else if (c == 4) {        /* a hex colour: ^Drrggbb[,rrggbb] */
                for (k = 0; k < 6 && ishex(*p); ++k)
                    ++p;
                if (k && *p == ',' && ishex(p[1])) {
                    ++p;
                    for (k = 0; k < 6 && ishex(*p); ++k)
                        ++p;
                }
            } else if (c == 9)
                emit(' ');
            continue;                   /* (bold, italics, reverse, reset ... dropped) */
        }
        if (c < 0x80) {
            emit(c);
            ++p;
        } else if (c >= 0xC2 && c <= 0xDF && cont(p, 1)) {
            fold(((c & 0x1F) << 6) | (p[1] & 0x3F));
            p += 2;
        } else if (c >= 0xE0 && c <= 0xEF && cont(p, 2)) {
            fold(((unsigned int)(c & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F));
            p += 3;
        } else if (c >= 0xF0 && c <= 0xF4 && cont(p, 3)) {
            emit('?');                  /* (beyond the BMP: emoji ...) */
            p += 4;
        } else {
            fold(c >= 0xA0 ? c : '?');  /* (not UTF-8: Latin-1) */
            ++p;
        }
    }
    *dp = 0;
    return dp;
}

/* Latin-1 s as UTF-8 onto d; the end */
/*---------------------------------------------------------------- lines shown */

/* tbuf = head + text cleaned, into window w */
static void __fastcall__ show(unsigned char w, unsigned char attr, const char *head, const char *text)
{
    unsigned char n = strlen(head);
    memcpy(tbuf, head, n);
    clean(tbuf + n, text ? text : "", LNMAX - n);
    sb_add(w, attr, tbuf);
}

#pragma bss-name (push, "OVL2BSS")
static char hd[NAMEMAX + 48];
static char nn[NAMEMAX];
#pragma bss-name (pop)

/* hd = a + b + c (V178: cut to hd, whatever their lengths) */
static void __fastcall__ hcat(const char *s)
{
    unsigned char n = strlen(hd);
    strncat(hd, s, sizeof hd - 1 - n);
}

static const char *__fastcall__ h3(const char *a, const char *b, const char *c)
{
    hd[0] = 0;
    hcat(a);
    hcat(b);
    hcat(c);
    return hd;
}

static unsigned char __fastcall__ ischan(const char *s)
{
    return *s == '#' || *s == '&' || *s == '+' || *s == '!';
}

static unsigned char __fastcall__ nickch(unsigned char c)
{
    return (c >= 'a' && c <= '}') || (c >= 'A' && c <= ']') || isdig(c) || c == '-' || c == '_' || c == '`' || c == '^';
}

/* our nick in t, as a word */
static unsigned char __fastcall__ mentions(const char *t)
{
    unsigned char n = strlen(me);
    const char *p;
    if (!n)
        return 0;
    for (p = t; *p; ++p)
        if (ieqn(p, me, n) && (p == t || !nickch(p[-1])) && !nickch(p[n]))
            return 1;
    return 0;
}

/* the window to show a line for: a channel's (else the server's) */
static unsigned char __fastcall__ wof(const char *name)
{
    signed char w = win_find(name);
    return w < 0 ? 0 : w;
}

/*---------------------------------------------------------------- sending */

static void __fastcall__ send2(const char *a, const char *b)
{
    strcpy(obuf, a);
    strcat(obuf, b);
    send_line(obuf);
}

/*---------------------------------------------------------------- a line in */

static void parse(void)
{
    char *p = rx, *q;
    np = 0;
    pfx = "";
    if (*p == '@') {                    /* IRCv3 tags: skipped */
        while (*p && *p != ' ')
            ++p;
        while (*p == ' ')
            ++p;
    }
    if (*p == ':') {
        pfx = ++p;
        while (*p && *p != ' ')
            ++p;
        if (*p)
            *p++ = 0;
    }
    while (*p == ' ')
        ++p;
    cmd = p;
    while (*p && *p != ' ')
        ++p;
    while (*p && np < 15) {
        *p++ = 0;
        while (*p == ' ')
            ++p;
        if (!*p)
            break;
        if (*p == ':') {
            par[np++] = p + 1;
            break;
        }
        par[np++] = p;
        while (*p && *p != ' ')
            ++p;
    }
    while (np < 15)
        par[np++] = "";
    np = 0;
    q = strchr(pfx, '!');
    uhost = q ? q + 1 : "";
    np = q ? q - pfx : strlen(pfx);
    if (np >= NAMEMAX)
        np = NAMEMAX - 1;
    memcpy(from, pfx, np);
    from[np] = 0;
    me_from = ieq(from, me);
}

static unsigned char __fastcall__ isserver(void)
{
    return !*uhost;
}

/* params a .. the last joined by spaces into hd (the numerics' text) */
static const char *__fastcall__ rest(unsigned char a)
{
    unsigned char i;
    tbuf[0] = 0;
    for (i = a; i < 15 && par[i][0]; ++i) {
        if (i > a)
            strcat(tbuf, " ");
        if (strlen(tbuf) + strlen(par[i]) > 500)
            break;
        strcat(tbuf, par[i]);
    }
    strcpy(obuf, tbuf);                 /* (show() writes tbuf) */
    return obuf;
}

static void nick_in_use(void)
{
    unsigned char n;
    if (cstate == C_UP) {
        show(cw, A_ERR, "-- ", rest(1));
        return;
    }
    if (++nick_try > 6) {
        show(0, A_ERR, "-- No nick could be had: ", rest(1));
        conn_quit(0);
        return;
    }
    if (nick_try == 1 && S.alt[0] && !ieq(S.alt, me))
        strncpy(me, S.alt, NICKLEN - 1);
    else {
        n = strlen(me);
        if (n < 16)
            me[n++] = '_';
        else
            me[15] = '0' + nick_try;
        me[n] = 0;
    }
    show(0, A_INFO, h3("-- ", par[1], " is taken: trying "), me);
    send2("NICK ", me);
}

static void names(void)
{
    signed char w = win_find(par[2]);
    char *p = par[3], *q;
    unsigned char m;
    if (w <= 0) {
        show(0, A_INFO, h3("-- Names on ", par[2], ": "), par[3]);
        return;
    }
    if (!W[w].names) {
        W[w].names = 1;
        nk_clear(w);
    }
    while (*p) {
        while (*p == ' ')
            ++p;
        if (!*p)
            break;
        m = ' ';
        if (strchr("~&@%+", *p)) {
            m = *p;
            while (strchr("~&@%+", *p) && *p)
                ++p;
        }
        q = p;
        while (*p && *p != ' ')
            ++p;
        if (*p)
            *p++ = 0;
        strncpy(from, q, NAMEMAX - 1);  /* (from: main RAM) */
        if (!*from)
            continue;
        if (W[w].nicks < NMAX)          /* (V178: counted, kept while there is room) */
            nk_join(w, from, m);
        else if (W[w].people != 0xFFFF) /* (a NAMES list names each once and was */
            ++W[w].people;              /* cleared at its start: no search when full) */
    }
    dirty |= D_STAT;
}

static void numeric(unsigned int n)
{
    signed char w;
    switch (n) {
    case 1:
        cstate = C_UP;
        strncpy(me, par[0], NICKLEN - 1);
        show(0, A_INFO, "", par[1]);
        dirty |= D_ALL;
        ov4(irc_welcome);
        return;
    case 5:                             /* (the server's options: not shown) */
        return;
    case 332:
        w = win_find(par[1]);
        if (w > 0) {
            clean(tbuf, par[2], TOPICMAX);
            topic_set(w, tbuf);
            show(w, A_INFO, "-- Topic: ", par[2]);
            return;
        }
        break;
    case 331:
        w = win_find(par[1]);
        if (w > 0) {
            show(w, A_INFO, "-- No topic is set", "");
            return;
        }
        break;
    case 333:
        return;
    case 353:
        names();
        return;
    case 366:
        w = win_find(par[1]);
        if (w > 0) {
            W[w].names = 0;
            strcpy(hd, "-- ");
            unum(hd + 3, W[w].people);
            strcat(hd, W[w].people == 1 ? " person here" : " people here");
            if (W[w].people > W[w].nicks) {     /* (V178) */
                strcat(hd, " (the list shows ");
                unum(hd + strlen(hd), W[w].nicks);
                strcat(hd, ")");
            }
            show(w, A_INFO, hd, "");
            dirty |= D_NICKS | D_STAT;
            return;
        }
        break;
    case 432: case 433: case 436: case 437:
        nick_in_use();
        return;
    case 375: case 372: case 376:       /* the MOTD: the server's window */
        show(0, A_INFO, "", par[1]);
        return;
    }
    if (n >= 400 && n < 600) {
        show(cw, A_ERR, "-- ", rest(1));
        return;
    }
    show(0, A_INFO, "", rest(1));
}

static void ctcp(unsigned char w, unsigned char notice)
{
    char *t = par[1] + 1, *e;
    e = strchr(t, 1);
    if (e)
        *e = 0;
    if (!memcmp(t, "ACTION", 6) && (t[6] == ' ' || !t[6])) {
        t += t[6] ? 7 : 6;
        show(w, mentions(t) ? A_MENTION : A_ACTION, h3("* ", from, " "), t);
        if (mentions(t))
            ding = 1;
        return;
    }
    if (notice) {
        show(0, A_NOTICE, h3("-- CTCP reply from ", from, ": "), t);
        return;
    }
    if (!memcmp(t, "VERSION", 7)) {
        strcpy(obuf, "NOTICE ");
        strcat(obuf, from);
        strcat(obuf, " :");
        strcat(obuf, version);
        send_line(obuf);
    } else if (!memcmp(t, "PING", 4)) {
        strcpy(obuf, "NOTICE ");
        strcat(obuf, from);
        strcat(obuf, " :\001");
        strncat(obuf, t, 400);          /* (V178: obuf's 520, whatever the PING's length) */
        strcat(obuf, "\001");
        send_line(obuf);
    }
    show(0, A_INFO, h3("-- CTCP ", t, " from "), from);
}

static void message_in(unsigned char notice)
{
    char *t = par[0], *text = par[1];
    signed char w;
    unsigned char a;
    if (text[0] == 1 && (notice || memcmp(text + 1, "ACTION", 6))) {
        ctcp(ischan(t) ? wof(t) : 0, notice);   /* (a CTCP query or reply: no window opened for it) */
        return;
    }
    if (ischan(t))
        w = wof(t);
    else if (notice || isserver() || cstate != C_UP) {
        w = notice && !isserver() && cstate == C_UP ? cw : 0;
    } else {
        w = win_find(from);             /* a private message: its window */
        if (w < 0) {
            w = win_new(W_QUERY, from);
            if (w < 0)
                w = 0;
            else {
                show(w, A_INFO, h3("-- A private conversation with ", from, ""), "");
                ding = 1;
            }
        }
    }
    if (text[0] == 1) {
        ctcp(w, notice);
        return;
    }
    if (notice) {
        show(w, A_NOTICE, h3("-", from[0] ? from : "server", "- "), text);
        return;
    }
    a = A_MSG;
    if (W[w].kind == W_QUERY && w != cw)
        ding = 1;
    if (ischan(t) && mentions(text)) {
        a = A_MENTION;
        ding = 1;
    }
    show(w, a, h3("<", from, "> "), text);
}

static void join(void)
{
    char *c = par[0];
    signed char w = win_find(c);
    if (me_from) {
        if (w < 0) {
            w = win_new(W_CHAN, c);
            if (w < 0) {
                show(0, A_ERR, "-- No room for another window: leaving ", c);
                send2("PART ", c);
                return;
            }
        } else
            nk_clear(w);
        W[w].joined = 1;
        W[w].names = 0;
        topic_set(w, 0);
        show(w, A_INFO, "-- You joined ", c);
        cw_req = w;
        return;
    }
    if (w > 0) {
        nk_join(w, from, ' ');
        show(w, A_INFO, h3("--> ", from, " joined"), "");
    }
}

static void part(void)
{
    signed char w = win_find(par[0]);
    if (w <= 0)
        return;
    if (me_from) {
        win_close(w);
        show(0, A_INFO, "-- You left ", par[0]);
        return;
    }
    if (nk_gone(w, from, 1))            /* (V178: one not kept left too) */
        show(w, A_INFO, h3("<-- ", from, " left "), par[1]);
}

static void kick(void)
{
    signed char w = win_find(par[0]);
    if (w <= 0)
        return;
    if (ieq(par[1], me)) {
        W[w].joined = 0;
        nk_clear(w);
        show(w, A_ERR, h3("-- You were kicked by ", from, ": "), par[2]);
        dirty |= D_TABS;
        return;
    }
    nk_gone(w, par[1], 1);
    hd[0] = 0;                          /* (V178: was 85 bytes at most into hd's 80) */
    hcat("<-- ");
    hcat(par[1]);
    hcat(" was kicked by ");
    hcat(from);
    hcat(": ");
    show(w, A_INFO, hd, par[2]);
}

static void quit(void)
{
    unsigned char w;
    for (w = 1; w < WMAX; ++w) {
        if (W[w].kind == W_CHAN && nk_gone(w, from, 0))
            ;
        else if (!(W[w].kind == W_QUERY && ieq(W[w].name, from)))
            continue;
        show(w, A_INFO, h3("<-- ", from, " quit "), par[0]);
    }
}

static void nick(void)
{
    unsigned char w, m;
    strncpy(nn, par[0], NAMEMAX - 1);
    if (me_from) {
        strncpy(me, nn, NICKLEN - 1);
        show(0, A_INFO, "-- You are now ", nn);
        dirty |= D_INPUT | D_STAT;
    }
    for (w = 1; w < WMAX; ++w) {
        if (W[w].kind == W_CHAN && nk_find(w, from) >= 0) {
            m = nk[0];
            nk_del(w, from);
            nk_add(w, nn, m);
        } else if (!(W[w].kind == W_QUERY && ieq(W[w].name, from)))
            continue;
        else {
            strncpy(W[w].name, nn, NAMEMAX - 1);
            dirty |= D_TABS;
        }
        show(w, A_INFO, h3("-- ", from, " is now "), nn);
    }
}

static void mode(void)
{
    signed char w;
    char *m;
    unsigned char on = 1, a = 2, c, pm;
    if (!ischan(par[0])) {
        show(0, A_INFO, h3("-- Your modes: ", par[1], " "), rest(2));
        return;
    }
    w = wof(par[0]);
    show(w, A_INFO, h3("-- ", from, " sets mode "), rest(1));
    for (m = par[1]; (c = *m) != 0; ++m) {
        pm = 0;
        switch (c) {
        case '+': on = 1; continue;
        case '-': on = 0; continue;
        case 'o': pm = '@'; break;
        case 'v': pm = '+'; break;
        case 'h': pm = '%'; break;
        case 'q': pm = '~'; break;
        case 'a': pm = '&'; break;
        case 'k': case 'b': case 'e': case 'I':
            ++a;
            continue;
        case 'l':
            if (on)
                ++a;
            continue;
        default:
            continue;
        }
        if (a < 15 && w > 0)
            nk_mode(w, par[a], pm, on);
        ++a;
    }
}

static void topic(void)
{
    signed char w = win_find(par[0]);
    if (w <= 0)
        return;
    clean(tbuf, par[1], TOPICMAX);
    topic_set(w, tbuf);
    show(w, A_INFO, h3("-- ", from, " set the topic: "), par[1]);
}

void irc_line(void)
{
    unsigned int n;
    parse();
    if (!strcmp(cmd, "PING")) {
        send2("PONG :", par[0]);
        return;
    }
    if (isdig(cmd[0]) && isdig(cmd[1]) && isdig(cmd[2]) && !cmd[3]) {
        n = (cmd[0] - '0') * 100 + (cmd[1] - '0') * 10 + cmd[2] - '0';
        numeric(n);
        return;
    }
    if (!strcmp(cmd, "PRIVMSG"))
        message_in(0);
    else if (!strcmp(cmd, "NOTICE"))
        message_in(1);
    else if (!strcmp(cmd, "JOIN"))
        join();
    else if (!strcmp(cmd, "PART"))
        part();
    else if (!strcmp(cmd, "QUIT"))
        quit();
    else if (!strcmp(cmd, "NICK"))
        nick();
    else if (!strcmp(cmd, "KICK"))
        kick();
    else if (!strcmp(cmd, "MODE"))
        mode();
    else if (!strcmp(cmd, "TOPIC"))
        topic();
    else if (!strcmp(cmd, "INVITE"))
        show(cw, A_INFO, h3("-- ", from, " invites you to "), par[1]);
    else if (!strcmp(cmd, "ERROR")) {
        clean(cwhy, par[0], sizeof cwhy);
        show(0, A_ERR, "-- ", par[0]);
    } else if (!strcmp(cmd, "PONG"))
        ;
    else
        show(0, A_INFO, h3("-- ", cmd, " "), rest(0));
}
