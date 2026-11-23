/* Veranda Claude: a turn's end (overlay 2; DECISIONS V114, V115).

   What a turn left: its reply kept (with a note when it was cut: the
   length limit, an error event, Stop, the connection), or its turn left
   out of what the API is sent (a refusal: the user's turn and the reply
   marked, a note; no reply: the user's text back in the input box), the
   API's error in a box and a note (the status's meaning: 401 the key,
   429 and 529 busy ...), the network's in a box. With Claude Code on my
   PC (the bridge, V115) its errors are its own words (the usage limit,
   not signed in ...) and a 401 is the bridge's password. ui.c draws what changed
   (msg: the status bar's text).

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

static char ebuf[52];

/* the API's error: its box, a note */
static void api_error(void)
{
    const char *a;
    char *p;
    unsigned int s = p_status;
    switch (s) {
    case 400: a = "The API refused the request (400):"; break;
    case 401: a = "The API key was not accepted (401):"; break;
    case 402: a = "A billing problem on the account (402):"; break;
    case 403: a = "Not allowed for this key (403):"; break;
    case 404: a = "Not found (404): is the model available?"; break;
    case 413: a = "The conversation is too large (413):"; break;
    case 429: a = "Claude is busy: too many requests (429)."; break;
    case 500: a = "The API had an error (500)."; break;
    case 529: a = "Claude is overloaded (529)."; break;
    default:
        strcpy(ebuf, "The API answered ");
        unum(ebuf + strlen(ebuf), s);
        strcat(ebuf, ":");
        a = ebuf;
    }
    strcpy(line, C.srv ? "(Bridge error " : "(API error ");
    p = unum(line + strlen(line), s);
    if (p_etype[0]) {
        strcpy(p, ", ");
        strcat(p, p_etype);
    }
    strcat(line, ": ");
    strncat(line, p_emsg[0] ? p_emsg : "no message", 120);
    strcat(line, ")");
    st_add(K_NOTE, line, strlen(line));
    if (C.srv) {                        /* (the bridge's own words: V115) */
        if (s == 401)
            message("The bridge password was not accepted (401).", "Check the password in Settings.");
        else {
            strcpy(ebuf, "Claude Code on the PC (");
            unum(ebuf + strlen(ebuf), s);
            strcat(ebuf, "):");
            message(ebuf, p_emsg);
        }
    } else if (s == 401)
        message(a, "Check your API key in Settings.");
    else if (s == 413)
        message(a, "Start a new one: File > New conversation.");
    else if (s == 429 || s == 529 || s == 500)
        message(a, "Busy: try again in a moment (Return).");
    else
        message(a, p_emsg);
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
        message(line, C.srv && e == TE_CONNECT ? "Is claude_bridge.py running on the PC?" : net_why());
        break;
    case TE_TIMEOUT:
        message("The API stopped sending.", "(nothing for 2 minutes: the connection was closed)");
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

/* the turn ended (tend, the parser's findings) */
void turn_end(void)
{
    unsigned char e = tend, got = p_text != 0, ok200 = p_status == 200;
    unsigned long t = ser_frames - tt0;
    char *p;
    tdone = 0;
    if (ok200 && !strcmp(p_stop, "refusal")) {
        if (got) {
            st_close();
            st_kind(t_rmsg, K_DECLINED);
        } else
            st_drop_last();
        st_kind(t_umsg, K_UNSENT);
        note("(Claude declined to answer this: a refusal. The turn is left out of the conversation: "
             "rephrase it and send it again.)");
        give_back();
        strcpy(msg, "Claude declined (a refusal): the turn is left out.");
    } else if (ok200 && got) {
        st_close();
        if (!strcmp(p_stop, "max_tokens"))
            note("(The reply reached its length limit, max_tokens, and was cut here.)");
        if (p_errev) {
            strcpy(line, "(The reply was cut by an error: ");
            strcat(line, p_etype);
            strcat(line, ": ");
            strncat(line, p_emsg, 100);
            strcat(line, ")");
            st_add(K_NOTE, line, strlen(line));
        } else if (e == TE_STOP)
            note("(Stopped: the part that came is kept.)");
        else if (e == TE_FULL)
            note("(The reply was cut: no more room for it.)");
        else if (e != TE_OK)
            note("(The connection ended before the reply did: the part that came is kept.)");
        if (p_fb)
            note("(Another model finished this reply: a server-side fallback.)");
        p = unum(msg, p_text);          /* (V149: no "Done: ", the status bar's 63 characters) */
        strcpy(p, " characters in ");
        p = unum(p + strlen(p), (t + 30) / 60);
        strcpy(p, " s");
        if (p_model[0] && strcmp(p_model, model_id[g_model])) {
            strcat(msg, " (answered by ");
            strcat(msg, p_model);
            strcat(msg, ")");
        }
        if (p_errev)
            message(C.srv ? "Claude Code on the PC:" : p_etype[0] ? "The reply was cut by an error:" : "The reply was cut.", p_emsg);
    } else {
        st_drop_last();
        st_kind(t_umsg, K_UNSENT);
        give_back();
        if (p_status && !ok200) {
            api_error();
            strcpy(msg, "Not sent: the API's error. Your text is back in the box.");
        } else if (ok200 && p_errev) {
            strcpy(line, "(Not answered: ");
            strcat(line, p_etype);
            strcat(line, ": ");
            strncat(line, p_emsg, 100);
            strcat(line, ")");
            st_add(K_NOTE, line, strlen(line));
            strcpy(msg, "Not answered. Your text is back in the box: Return sends it again.");
            message(C.srv ? "Claude Code on the PC:" : !strcmp(p_etype, "overloaded_error") ? "Claude is overloaded." : "The API sent an error:",
                    !strcmp(p_etype, "overloaded_error") ? "Busy: try again in a moment (Return)." : p_emsg);
        } else if (e == TE_STOP) {
            note("(Stopped before Claude answered: the turn is left out.)");
            strcpy(msg, "Stopped. Your text is back in the box.");
        } else if (ok200 && e == TE_OK) {
            note("(Claude sent an empty reply: the turn is left out.)");
            strcpy(msg, "An empty reply.");
        } else {
            note("(Not sent: the connection failed.)");
            strcpy(msg, "Not sent. Your text is back in the box.");
            net_box(e);
        }
    }
    st_prot = st_used;
}
