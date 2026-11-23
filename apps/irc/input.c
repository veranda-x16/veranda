/* Veranda Chat: the input line's commands and messages, the
   registration (overlay 4; DECISIONS V111).

   The input line: /join /part /msg /query /nick /me /topic /notice
   /quit /raw (/quote) /close /clear /help; any other /command is sent
   as it is (/whois nick ...); text goes to the window shown, cut to
   IRC's 512 bytes (with room for the prefix the server puts before it
   when it passes it on) at a space; the set's letters typed (ISO-8859-16,
   V143) are sent as UTF-8.
   At the connection: PASS (if the server has a password), NICK, USER;
   after 001 the server's channels joined (one JOIN, by commas).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrcs.h>
#include "chat.h"
#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
#pragma bss-name ("OVL4BSS")

static char *__fastcall__ enc(char *d, const char *s, unsigned int n)
{
    unsigned char c;
    const char *d0 = d;
    while (n-- && d - d0 < 450) {       /* (a /raw of 480 accented letters is cut: obuf's room) */
        c = *s++;
        if (c < 0x80)
            *d++ = c;
        else
            d += cs_utf8(c, d);         /* (the set's: 2 or 3 bytes) */
    }
    *d = 0;
    return d;
}

/* tbuf = head + text (typed: the set's already), into window w */
static void __fastcall__ note(unsigned char w, unsigned char attr, const char *head, const char *text)
{
    strcpy(tbuf, head);
    strncat(tbuf, text, LNMAX - 1 - strlen(tbuf));
    sb_add(w, attr, tbuf);
}

static char hd[NAMEMAX + 48];

static const char *__fastcall__ h3(const char *a, const char *b, const char *c)
{
    strcpy(hd, a);
    strncat(hd, b, NAMEMAX);
    strcat(hd, c);
    return hd;
}

static unsigned char __fastcall__ ischan(const char *s)
{
    return *s == '#' || *s == '&' || *s == '+' || *s == '!';
}

static unsigned char __fastcall__ nickch(unsigned char c)
{
    return (c >= 'a' && c <= '}') || (c >= 'A' && c <= ']') || (c >= '0' && c <= '9') || c == '-' || c == '_';
}

/*---------------------------------------------------------------- sending */

static void __fastcall__ send2(const char *a, const char *b)
{
    strcpy(obuf, a);
    strcat(obuf, b);
    send_line(obuf);
}

void irc_register(void)
{
    char *p;
    const char *s;
    unsigned char n = 0;
    if (S.pass[0])
        send2("PASS ", S.pass);
    send2("NICK ", me);
    strcpy(obuf, "USER ");
    p = obuf + 5;
    for (s = S.nick; *s && n < 10; ++s)
        if (nickch(*s) && *s != '^' && *s != '`') {
            *p++ = ilower(*s);
            ++n;
        }
    if (!n) {
        strcpy(p, "veranda");
        p += 7;
    }
    strcpy(p, " 0 * :");
    strcat(p, S.real[0] ? S.real : "Veranda Chat user");
    send_line(obuf);
    note(0, A_INFO, "-- Registering as ", me);
}

void irc_welcome(void)
{
    char *p = obuf + 5, *s = S.chans;
    if (!*s)
        return;
    strcpy(obuf, "JOIN ");
    while (*s) {
        while (*s == ' ' || *s == ',')
            ++s;
        if (!*s)
            break;
        if (p != obuf + 5)
            *p++ = ',';
        if (!ischan(s))
            *p++ = '#';
        while (*s && *s != ' ' && *s != ',')
            *p++ = *s++;
    }
    *p = 0;
    if (p != obuf + 5)
        send_line(obuf);
}

/* the longest text (encoded) a PRIVMSG to t can carry: 512 less CR LF,
   the command, and the prefix the server puts before it when it passes
   it on (:nick!user@host with a host of up to 63) */
static unsigned int __fastcall__ room(const char *t, unsigned char extra)
{
    return 510 - (strlen(me) + 1 + 1 + 10 + 1 + 63 + 1) - (8 + strlen(t) + 2) - extra;
}

/* text (the set's, n bytes) to t as PRIVMSG (action: CTCP ACTION), in
   pieces that fit, each shown in window w */
static void __fastcall__ say(unsigned char w, const char *t, const char *text, unsigned char action)
{
    unsigned int lim = room(t, action ? 9 : 0), i, e, sp, bytes, n = strlen(text);
    char *p;
    while (n) {
        bytes = 0;
        sp = 0;
        for (i = 0; i < n; ++i) {
            e = (unsigned char)text[i] < 0x80 ? 1 : cs_uni(text[i]) < 0x800 ? 2 : 3;
            if (bytes + e > lim)
                break;
            bytes += e;
            if (text[i] == ' ')
                sp = i;
        }
        if (i < n && sp > i / 2)
            i = sp;                     /* (cut at a space: it is not sent) */
        strcpy(obuf, "PRIVMSG ");
        strcat(obuf, t);
        strcat(obuf, action ? " :\001ACTION " : " :");
        p = enc(obuf + strlen(obuf), text, i);
        if (action) {
            *p++ = 1;
            *p = 0;
        }
        send_line(obuf);
        if (action)
            strcpy(tbuf, h3("* ", me, " "));
        else if (W[w].kind == W_SERV || !ieq(W[w].name, t))
            strcpy(tbuf, h3("-> *", t, "* "));
        else
            strcpy(tbuf, h3("<", me, "> "));
        p = tbuf + strlen(tbuf);
        memcpy(p, text, i);
        for (e = i; e > 1 && p[e - 1] == ' '; --e)
            ;
        p[e] = 0;
        sb_add(w, A_OWN, tbuf);
        text += i;
        n -= i;
        while (*text == ' ' && n) {
            ++text;
            --n;
        }
    }
}

/*---------------------------------------------------------------- the input line */

static char *arg;                       /* after the command's word */

/* the next word of arg (0-terminated in place), arg after it */
static char *word(void)
{
    char *w;
    while (*arg == ' ')
        ++arg;
    w = arg;
    while (*arg && *arg != ' ')
        ++arg;
    if (*arg)
        *arg++ = 0;
    while (*arg == ' ')
        ++arg;
    return w;
}

static unsigned char online(void)
{
    if (cstate == C_UP)
        return 1;
    note(cw, A_ERR, "-- Not connected (Server > Servers... connects).", "");
    return 0;
}

static const char *__fastcall__ chan_or_cw(void)
{
    if (ischan(arg))
        return word();
    if (W[cw].kind == W_CHAN)
        return W[cw].name;
    return 0;
}

static unsigned char __fastcall__ is(const char *c, const char *name)
{
    return ieq(c, name);
}

static void help(void)
{
    note(cw, A_INFO, "-- /join #channel, /part [reason], /msg nick text, /query nick, /me action,", "");
    note(cw, A_INFO, "-- /nick new, /topic [text], /notice nick text, /raw line (/quote), /close,", "");
    note(cw, A_INFO, "-- /clear, /quit [reason]; any other /command is sent as it is (/whois nick).", "");
}

void irc_input(void)
{
    char *c;
    const char *t;
    signed char w;
    arg = inbuf;
    if (inbuf[0] != '/' || inbuf[1] == '/') {
        if (inbuf[0] == '/')
            ++arg;
        if (!*arg)
            return;
        if (W[cw].kind == W_SERV) {
            note(cw, A_ERR, "-- This is the server's window: /join a channel, or /msg nick text.", "");
            return;
        }
        if (online())
            say(cw, W[cw].name, arg, 0);
        return;
    }
    ++arg;
    c = word();
    if (is(c, "me")) {
        if (W[cw].kind != W_SERV && *arg && online())
            say(cw, W[cw].name, arg, 1);
    } else if (is(c, "join") || is(c, "j")) {
        if (!online())
            return;
        t = word();
        strcpy(obuf, "JOIN ");
        if (!ischan(t))
            strcat(obuf, "#");
        strcat(obuf, t);
        if (*arg) {
            strcat(obuf, " ");
            strcat(obuf, arg);
        }
        if (*t)
            send_line(obuf);
    } else if (is(c, "part") || is(c, "leave")) {
        t = chan_or_cw();
        if (!t || !online())
            return;
        strcpy(obuf, "PART ");
        strcat(obuf, t);
        if (*arg) {
            strcat(obuf, " :");
            enc(obuf + strlen(obuf), arg, strlen(arg));
        }
        send_line(obuf);
    } else if (is(c, "msg") || is(c, "query") || is(c, "q")) {
        t = word();
        if (!*t)
            return;
        w = win_find(t);
        if (c[0] == 'q' || c[0] == 'Q') {
            if (w < 0 && !ischan(t))
                w = win_new(W_QUERY, t);
            if (w < 0) {
                note(cw, A_ERR, "-- No room for another window: /close one.", "");
                return;
            }
            cw_req = w;
        } else if (w < 0)
            w = cw;
        if (*arg && online())
            say(w, t, arg, 0);
    } else if (is(c, "nick")) {
        t = word();
        if (!*t)
            return;
        if (cstate == C_UP)
            send2("NICK ", t);
        else
            strncpy(S.nick, t, 16);
    } else if (is(c, "topic")) {
        t = chan_or_cw();
        if (!t || !online())
            return;
        strcpy(obuf, "TOPIC ");
        strcat(obuf, t);
        if (*arg) {
            strcat(obuf, " :");
            enc(obuf + strlen(obuf), arg, strlen(arg));
        }
        send_line(obuf);
    } else if (is(c, "notice")) {
        t = word();
        if (!*t || !online())
            return;
        strcpy(obuf, "NOTICE ");
        strcat(obuf, t);
        strcat(obuf, " :");
        enc(obuf + strlen(obuf), arg, strlen(arg));
        send_line(obuf);
        note(cw, A_OWN, h3("-> -", t, "- "), arg);
    } else if (is(c, "quit")) {
        enc(tbuf, arg, strlen(arg));
        conn_quit(*arg ? tbuf : 0);
    } else if (is(c, "raw") || is(c, "quote")) {
        if (*arg && online()) {
            enc(obuf, arg, strlen(arg));
            send_line(obuf);
            note(0, A_OWN, "-> ", obuf);
        }
    } else if (is(c, "close")) {
        if (W[cw].kind == W_CHAN && W[cw].joined && cstate == C_UP)
            send2("PART ", W[cw].name);
        else
            win_close(cw);
    } else if (is(c, "clear")) {
        sb_clear(cw);
    } else if (is(c, "help")) {
        help();
    } else if (online()) {              /* any other: as it is (WHOIS ...) */
        for (t = c; *t; ++t)
            *(char *)t = *t >= 'a' && *t <= 'z' ? *t - 32 : *t;
        strcpy(obuf, c);
        if (*arg) {
            strcat(obuf, " ");
            enc(obuf + strlen(obuf), arg, strlen(arg));
        }
        send_line(obuf);
    }
}

/*---------------------------------------------------------------- Tab (ui.c's key) */

static unsigned int comp_ws, comp_end;
static int comp_i;
static char comp_pre[NICKLEN];

static void __fastcall__ ins(const char *s)
{
    while (*s && in_len < INMAX) {
        memmove(inbuf + in_cur + 1, inbuf + in_cur, in_len - in_cur + 1);
        inbuf[in_cur++] = *s++;
        ++in_len;
    }
}

/* Tab: the word before the cursor completed from the channel's nicks
   (again: the next one) */
void in_complete(void)
{
    unsigned int n = W[cw].nicks, k;
    unsigned char pl;
    int i;
    if (W[cw].kind != W_CHAN || !n)
        return;
    if (!comp_on) {
        for (comp_ws = in_cur; comp_ws && inbuf[comp_ws - 1] != ' '; --comp_ws)
            ;
        pl = in_cur - comp_ws;
        if (!pl || pl >= NICKLEN)
            return;
        memcpy(comp_pre, inbuf + comp_ws, pl);
        comp_pre[pl] = 0;
        comp_i = -1;
        comp_end = in_cur;
    }
    pl = strlen(comp_pre);
    for (k = 1; k <= n; ++k) {
        i = (comp_i + k) % n;
        nk_get(cw, i);
        if (ieqn(nk + 1, comp_pre, pl) && !ieq(nk + 1, me))
            break;
    }
    if (k > n)
        return;
    comp_i = i;
    comp_on = 1;
    memmove(inbuf + comp_ws, inbuf + comp_end, in_len - comp_end + 1);   /* (the word, or the last completion, out) */
    in_len -= comp_end - comp_ws;
    in_cur = comp_ws;
    ins(nk + 1);
    ins(comp_ws ? " " : ": ");
    comp_end = in_cur;
}

/*---------------------------------------------------------------
  the font: the X16 ROM's ISO-8859-15 set (ROM bank 6), its $A0-$FF the
  ROM's ISO-8859-16 set (Veranda's, V140, V143: found by its A ogonek);
  (V178) here, in overlay 4, from main.c: main RAM's room went to store.c
 ---------------------------------------------------------------*/
static const unsigned char sig0[8] = { 0xC3, 0x99, 0x91, 0x91, 0x91, 0x9F, 0xC1, 0xFF };
static const unsigned char sigA[8] = { 0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x66, 0x00 };
static const unsigned char sigL10[8] = { 0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x0C, 0x06 };

void load_font(void)
{
    unsigned char keep, ok = 0;
    unsigned int a;
    asm("sei");
    keep = *(unsigned char *)1;
    *(unsigned char *)1 = 6;
    for (a = 0xC000; a; a += 0x800)
        if (!memcmp((void *)a, sig0, 8) && !memcmp((void *)(a + 0x41 * 8), sigA, 8)) {
            memcpy(font, (void *)(a + 256), sizeof font);
            ok = 1;
            break;
        }
    if (!ok)
        memcpy(font, (void *)0xC900, sizeof font);
    for (a = 0xC008; a; a += 8)
        if (*(unsigned char *)a == 0x18 && !memcmp((void *)a, sigL10, 8)) {
            memcpy(font + (0xA0 - 32) * 8, (void *)(a - 8), 96 * 8);
            break;
        }
    *(unsigned char *)1 = keep;
    asm("cli");
}
