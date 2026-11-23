/* Veranda Ask: a request's end (overlay 2; DECISIONS V116).

   A turn (rq RQ_CHAT): its reply kept when text came (a note when it was
   cut: incomplete, failed, an error event, Stop, the connection ended
   before response.completed); else the turn left out, the user's text
   back in the input box, the error in a box and a note. With the ChatGPT
   plan a 401 renews the sign-in (the refresh token, once) and sends the
   turn again, unless (V131) a clock to trust says the token is still good
   and the error does not say it expired: then nothing is renewed (OpenAI
   renews near a token's end; a 401 alone does not end a sign-in) and the
   box points to the PC's check, the tokens kept; a second 401, or a renewal that the server refuses for
   good (invalid_grant, refresh_token_reused ...), says: sign in again from
   your PC. The plan's own codes have their own words (the usage limit:
   chatgpt.com/settings/usage; not eligible: Plus or Pro; unavailable: try
   again later). A network failure never drops the credentials.

   The renewal (RQ_REFRESH; V129): whatever came whole of a 200's tokens is
   kept (ASK.CFG written first), however the connection ended (the server
   has rotated the refresh token already); then the turn again (or, after
   Esc, its end). What could not be kept is said precisely (r_why).
   Each request's end writes ASK.LOG (log.c): lg_end.

   The sign-in through the PC (RQ_SIGNIN): the helper's set kept when it
   said end=ok; a note, the plan's notice the first time; else its words
   in a box.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "claude.h"
#pragma code-name ("OVERLAY2")
#pragma rodata-name ("OVL2RO")
#pragma bss-name ("OVL2BSS")

/* a note (s here, in this bank: copied through line, 128 bytes at a time) */
static void __fastcall__ note(const char *s)
{
    unsigned int n = strlen(s), k;
    if (!st_open(K_NOTE))
        return;
    for (; n; n -= k, s += k) {
        k = n > 128 ? 128 : n;
        memcpy(line, s, k);
        st_append(line, k);
    }
    st_close();
}

/* line as a note */
static void lnote(void)
{
    st_add(K_NOTE, line, strlen(line));
}

/* the user's text back in the input box (a turn that did not happen) */
static void give_back(void)
{
    unsigned int n;
    if (in_len)
        return;
    st_msg(t_umsg);
    n = st_n > INMAX ? INMAX : st_n;
    st_copy(t_umsg + 3, inbuf, n);
    inbuf[n] = 0;
    in_len = in_cur = n;
}

/* the turn left out */
static void left_out(void)
{
    st_drop_last();
    st_kind(t_umsg, K_UNSENT);
    give_back();
}

static const char *net_why(void)
{
    switch (tnet) {
    case NET_ERR: return "(refused, or no such host)";
    case NET_ETIMEOUT: return "(no answer)";
    case NET_EBADARG: return "(a bad host name)";
    case NET_ENOSOCK: return "(no free connection)";
    }
    return "(the modem's connection failed)";
}

static void __fastcall__ net_box(unsigned char e)
{
    switch (e) {
    case TE_CONNECT:
    case TE_NET:
        strcpy(line, e == TE_CONNECT ? "Could not connect to " : "The connection to ");
        strncat(line, C.host, 30);
        if (e == TE_NET)
            strcat(line, " failed");
        message(line, rq == RQ_SIGNIN && e == TE_CONNECT ? "Is chatgpt_signin.py running on the PC?" : net_why());
        break;
    case TE_TIMEOUT:
        message("The server stopped sending.", "(nothing for 2 minutes: the connection was closed)");
        break;
    case TE_CLOSED:
        message("The connection closed", "before the reply ended.");
        break;
    case TE_MODEM:
        message("The modem does not answer.", "(TexElec's Serial & ESP32 Network Card)");
        break;
    case TE_NOCARD:
        message("No network card was found.", "(TexElec's Serial & ESP32 Network Card)");
        break;
    }
}

static unsigned char __fastcall__ is(const char *code)
{
    return !strcmp(p_etype, code);
}

static const char again[] = "Sign in again from your PC: Settings, Continue with ChatGPT.";

/* the plan's codes (in an error's body or a failed reply): their box; 0: not one */
static unsigned char plan_box(void)
{
    if (is("subscription_sharing_usage_limit_exceeded")) {
        note("(Usage limit reached. Review your plan or this app's limit in ChatGPT settings: "
             "chatgpt.com/settings/usage)");
        message("Usage limit reached. Review your plan or this app's", "limit: ChatGPT settings, chatgpt.com/settings/usage");
    } else if (is("subscription_sharing_user_not_eligible")) {
        note("(Your ChatGPT plan cannot be used in this app: ChatGPT Plus or Pro is needed. "
             "Or use an OpenAI API key: Settings.)");
        message("Your ChatGPT plan can't be used in this app.", "Plus or Pro is needed. Or use an OpenAI API key.");
    } else if (is("subscription_sharing_usage_unavailable") || is("subscription_sharing_user_unavailable")) {
        note("(Plan usage is not available right now: try again later.)");
        message("Plan usage is not available right now.", "Try again later.");
    } else if (is("subscription_sharing_unsupported_capability")) {
        message("Not supported with the ChatGPT plan:", p_param[0] ? p_param : p_emsg);
    } else if (is("subscription_sharing_route_not_supported")) {
        message("Not available with the ChatGPT plan.", p_emsg);
    } else if (is("subscription_sharing_invalid_user")) {
        note(again);
        message("Sign in again from your PC:", "Settings, Continue with ChatGPT.");
    } else
        return 0;
    return 1;
}

static char ebuf[52];
static unsigned char lg_done;

/* (V129) the request's result into its log, ASK.LOG written (before
   another request starts: it makes its own) */
static void __fastcall__ lg_end(const char *why)
{
    lg_s("\nresult: ");
    lg_s(why);
    lg_c('\n');
    ovl(lg_save);
    lg_done = 1;
}

/* an error status: its note, its box */
static void api_error(void)
{
    const char *a;
    char *p;
    unsigned int s = p_status;
    strcpy(line, "(Error ");
    p = unum(line + strlen(line), s);
    if (p_etype[0]) {
        strcpy(p, ", ");
        strncat(p, p_etype, 50);
    }
    strcat(line, ": ");
    strncat(line, p_emsg[0] ? p_emsg : "no message", 120);
    strcat(line, ")");
    lnote();
    if (plan_box())
        return;
    if (s == 401 && !C.srv && !t_retry) {      /* (V131: a fresh token refused: not renewed, kept) */
        message("The plan did not accept the sign-in (401).", "Kept. On the PC: chatgpt_signin.py --card --check");
        return;
    }
    if (s == 401 && !C.srv) {
        note(again);
        message("Sign in again from your PC:", "Settings, Continue with ChatGPT.");
        return;
    }
    switch (s) {
    case 400: a = "The request was refused (400):"; break;
    case 401: a = "The API key was not accepted (401)."; break;
    case 403: a = "Not allowed (403):"; break;
    case 404: a = "Not found (404): is the model available?"; break;
    case 413: a = "The conversation is too large (413):"; break;
    case 429: a = "Too many requests, or no credit (429):"; break;
    case 500: case 502: case 503: a = "OpenAI had an error, or is busy:"; break;
    default:
        strcpy(ebuf, "The server answered ");
        unum(ebuf + strlen(ebuf), s);
        strcat(ebuf, ":");
        a = ebuf;
    }
    if (s == 401)
        message(a, "Check your API key in Settings.");
    else if (s == 413)
        message(a, "Start a new one: File > New conversation.");
    else if (s >= 500)
        message(a, "Try again in a moment (Return).");
    else
        message(a, p_emsg);
}

/* an error event or response.failed: its note */
static void ev_note(const char *how)
{
    strcpy(line, how);
    strncat(line, p_etype[0] ? p_etype : "error", 50);
    strcat(line, ": ");
    strncat(line, p_emsg, 100);
    strcat(line, ")");
    lnote();
}

static void chat_end(void)
{
    unsigned char e = tend, got = p_text != 0, ok200 = p_status == 200;
    unsigned long t = ser_frames - tt0;
    char *p;
    if (p_status == 401 && !got && !C.srv && !t_retry && e != TE_STOP
        && (ovl(tok_due), !t_ok || t_due || strstr(p_etype, "xpired") || strstr(p_emsg, "xpired"))) {
        lg_end("401: the sign-in renewed, the turn sent again");
        lg_keep = 1;
        ov5(ask_renew);                 /* (the sign-in renewed, then the turn again; not started: its end next) */
        strcpy(msg, "Renewing the sign-in ...");
        return;
    }
    if (ok200 && got) {
        st_close();
        if (p_inc) {
            strcpy(line, "(The reply is incomplete: ");
            strcat(line, p_stop[0] ? p_stop : "cut short");
            strcat(line, ".)");
            lnote();
        }
        if (p_errev)
            ev_note("(The reply was cut by an error: ");
        else if (e == TE_STOP)
            note("(Stopped: the part that came is kept.)");
        else if (e == TE_FULL)
            note("(The reply was cut: no more room for it.)");
        else if (!p_ok && !p_inc)
            note("(The reply was interrupted: the connection ended before it was complete. The part that came is kept.)");
        p = unum(msg, p_text);          /* (V149: no "Done: ", the status bar's 63 characters) */
        strcpy(p, " characters in ");
        p = unum(p + strlen(p), (t + 30) / 60);
        strcpy(p, " s");
        if (p_errev && !plan_box())
            message("The reply was cut by an error:", p_emsg);
    } else {
        left_out();
        if (p_status && !ok200) {
            api_error();
            strcpy(msg, "Not sent: the server's error. Your text is back in the box.");
        } else if (ok200 && p_errev) {
            ev_note("(Not answered: ");
            strcpy(msg, "Not answered. Your text is back in the box: Return sends it again.");
            if (!plan_box())
                message("The server sent an error:", p_emsg);
        } else if (e == TE_STOP) {
            note("(Stopped before the reply came: the turn is left out.)");
            strcpy(msg, "Stopped. Your text is back in the box.");
        } else if (ok200 && (e == TE_OK || p_ok)) {
            note("(An empty reply: the turn is left out.)");
            strcpy(msg, "An empty reply.");
        } else {
            note("(Not sent: the connection failed.)");
            strcpy(msg, "Not sent. Your text is back in the box.");
            net_box(e);
        }
    }
    st_prot = st_used;
}

static const char *const dead[] = { "invalid_grant", "invalid_refresh_token", "token_expired",
    "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused", 0 };

/* the renewal's end: the turn again, or why not */
static void renew_end(void)
{
    unsigned char e = tend, i;
    ov5(ask_whole);
    if (tgo) {                          /* (V129: however it ended) */
        ov5(ask_commit);
        if (sv_fail)
            note("(ASK.CFG could not be written: the renewed sign-in is kept until Veranda Ask quits.)");
    }
    if (r_why)
        ovv(lg_why);                    /* (r_txt: why; a warning only in ASK.LOG when the turn goes) */
    if (tgo && sl.acc) {
        lg_end(r_why ? r_txt : "kept");
        if (t_cancel) {
            t_cancel = 0;
            left_out();
            note("(Stopped before the reply came: the turn is left out.)");
            strcpy(msg, "Stopped. Your text is back in the box.");
            st_prot = st_used;
            return;
        }
        ov5(ask_again);
        strcpy(msg, "Signed in again: sending ...");
        return;
    }
    t_cancel = 0;
    left_out();
    if (p_status == 200) {               /* (V129: why, precisely) */
        strcpy(line, "(The sign-in could not be renewed: ");
        strcat(line, r_txt);
        strcat(line, tgo ? ". Its new refresh token is kept: Return tries again.)" : ".)");
        lnote();
        lg_end(r_txt);
        message("The sign-in could not be renewed:", r_txt);
        strcpy(msg, "Not sent. Your text is back in the box.");
    } else if (p_status) {
        for (i = 0; dead[i] && !is(dead[i]); ++i)
            ;
        strcpy(line, "(The sign-in could not be renewed: ");
        p_etype[0] ? strncat(line, p_etype, 40) : unum(line + strlen(line), p_status);
        strcat(line, ": ");
        strncat(line, p_emsg, 100);
        strcat(line, ")");
        lnote();
        if (dead[i]) {                  /* (the refresh token is dead: sign in again) */
            ov5(ask_forget);
            ov4(ask_bar);
            note(again);
            message("The sign-in has ended: sign in again from your PC.", "Settings, Continue with ChatGPT.");
            strcpy(msg, "Signed out: sign in again from your PC (Settings).");
        } else {
            strcpy(ebuf, "The sign-in could not be renewed (");
            unum(ebuf + strlen(ebuf), p_status);
            strcat(ebuf, "):");
            message(ebuf, p_emsg[0] ? p_emsg : p_etype[0] ? p_etype : "(no reason given: see /VERANDA/.SYSTEM/ASK.LOG)");
            strcpy(msg, "Not sent. Your text is back in the box.");
        }
    } else {
        note("(Not sent: the sign-in could not be renewed, the connection failed. It is kept: try again.)");
        strcpy(msg, "Not sent. Your text is back in the box.");
        net_box(e == TE_STOP ? TE_CLOSED : e);
    }
    st_prot = st_used;
}

/* the sign-in through the PC: its end */
static void signin_end(void)
{
    unsigned char e = tend;
    char *p;
    ov5(ask_whole);
    if (p_status == 200 && kv_ok && tgo) {     /* (end=ok: the helper's set came whole) */
        ov5(ask_commit);
        strcpy(line, "(Signed in with ChatGPT");
        if (sl.login) {
            strcat(line, " as ");
            p = line + strlen(line);
            bk_get(tbank + tlive, TB_LOGIN, p, sl.login);
            p[sl.login] = 0;
        }
        strcat(line, ". Eligible usage in this app uses your ChatGPT plan; manage it at chatgpt.com/settings/usage.)");
        lnote();
        if (sv_fail)
            message("ASK.CFG cannot be written:", "the sign-in is kept until Veranda Ask quits.");
        strcpy(msg, "Signed in: using your ChatGPT plan. Type below.");
        ov4(ask_bar);
        if (!notice)
            ov4(notice_show);
        return;
    }
    if (e == TE_STOP) {
        strcpy(msg, "The sign-in was cancelled.");
        return;
    }
    strcpy(msg, "Not signed in.");
    if (p_status == 403)
        message("The code was not accepted:", p_emsg[0] ? p_emsg : "type the code the PC shows.");
    else if (p_status)
        message("The sign-in did not finish:", p_emsg[0] ? p_emsg : "(the helper's reply was cut)");
    else
        net_box(e);
}

void turn_end(void)
{
    tdone = 0;
    lg_done = 0;
    if (rq == RQ_SIGNIN)
        signin_end();
    else if (rq == RQ_REFRESH)
        renew_end();
    else
        chat_end();
    if (!lg_done)
        lg_end(msg);
}
