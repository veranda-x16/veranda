/* Veranda Ask: what the reply's parser keeps (included by apps/claude/parse.c
   with -DASK, in overlay 3; DECISIONS V116).

   The Responses API's server-sent events (a turn, rq RQ_CHAT; each data
   line one JSON object, its "type" first):
     response.output_text.delta   delta: the text, into dtext as it comes
     response.completed           the reply's end (the only success);
                                  response.model, response.usage's
                                  input_tokens, output_tokens
     response.incomplete          the end, cut: incomplete_details.reason
     response.failed              response.error.code, .message
     error                        code, message (param)
   A status that is not 200: {"error": {"code", "message", "type",
   "param"}} or {"detail": "..."}. The token endpoint's reply (rq
   RQ_REFRESH): access_token and refresh_token made lines "access=...",
   "refresh=..." and expires_in "expires=N" in dtext (overlay 5's kv_reply
   keeps them, in a RAM bank: an access token is about 2 KB); an OAuth
   error as {"error": "invalid_grant", "error_description": "..."} or
   the API's error object. The id_token is skipped (the PC's helper
   checked it at the sign-in).

   MIT licence (see LICENSE). */

#define K_OTHER   0
#define K_TYPE    1
#define K_DELTA   2
#define K_CODE    3
#define K_MESSAGE 4
#define K_ERROR   5
#define K_RESP    6
#define K_MODEL   7
#define K_USAGE   8
#define K_IN      9
#define K_OUT     10
#define K_DETAIL  11
#define K_PARAM   12
#define K_ACCESS  13
#define K_REFRESH 14
#define K_EXPIRES 15
#define K_EDESC   16
#define K_INCOMP  17
#define K_REASON  18
#define K_ITD     19
#define K_CACHED  20
static const char *const keys[] = { "", "type", "delta", "code", "message", "error", "response", "model",
    "usage", "input_tokens", "output_tokens", "detail", "param", "access_token", "refresh_token",
    "expires_in", "error_description", "incomplete_details", "reason", "input_tokens_details", "cached_tokens" };
#define NKEYS 21

static unsigned char __fastcall__ key_of(void)
{
    unsigned char i;
    for (i = 1; i < NKEYS; ++i)
        if (!strcmp(kb, keys[i]))
            return i;
    return K_OTHER;
}

static void __fastcall__ capture(char *to, unsigned char n)
{
    cap = to;
    capn = n;
}

/* a string value begins: where it goes */
static void str_begin(void)
{
    unsigned char k = jk[jd], up = jd > 1 ? jk[jd - 1] : K_OTHER;
    vto = V_CAP;
    capi = 0;
    if (jd == 1 && rq == RQ_REFRESH && (k == K_ACCESS || k == K_REFRESH || k == K_EXPIRES)) {
        vto = V_TEXT;                   /* (a line for kv_reply; V129: "expires_in": "3600" too) */
        outs(k == K_ACCESS ? "access=" : k == K_REFRESH ? "refresh=" : "expires=");
        kvs = 1;
        return;
    }
    if (jd == 1 && k == K_TYPE)
        capture(evtype, sizeof evtype);
    else if (jd == 1 && k == K_DELTA && rq == RQ_CHAT && !strcmp(evtype, "response.output_text.delta")) {
        vto = V_TEXT;
        return;
    } else if ((jd == 1 && (k == K_CODE || k == K_ERROR)) || (up == K_ERROR && k == K_CODE)
               || (up == K_ERROR && k == K_TYPE && !p_etype[0]))
        capture(p_etype, sizeof p_etype);       /* (the code; error.type only without one) */
    else if ((jd == 1 && (k == K_MESSAGE || k == K_DETAIL || k == K_EDESC)) || (up == K_ERROR && k == K_MESSAGE))
        capture(p_emsg, sizeof p_emsg);
    else if ((jd == 1 || up == K_ERROR) && k == K_PARAM)
        capture(p_param, sizeof p_param);
    else if (jd == 2 && up == K_RESP && k == K_MODEL)
        capture(p_model, sizeof p_model);
    else if (up == K_INCOMP && k == K_REASON)
        capture(p_stop, sizeof p_stop);
    else
        vto = V_NONE;
    if (vto == V_CAP)
        cap[0] = 0;
}

/* (V129) the log: a renewal's key and its value's length (never the value) */
static void __fastcall__ lg_key(unsigned int n)
{
    if (rq != RQ_REFRESH || p_status != 200 || jd != 1)
        return;
    lg_s(kb);
    lg_c(' ');
    lg_u(n);
    lg_s(", ");
}

static void str_end(void)
{
    lg_key(jl - 1);
    if (kvs) {
        out('\n');
        kvs = 0;
    }
    vto = V_NONE;
}

/* a number (or true, false, null) ended */
static void lit_end(void)
{
    unsigned long v = 0;
    unsigned char i, k = jk[jd];
    nb[nn] = 0;
    lg_key(nn);
    if (jd == 1 && rq == RQ_REFRESH && k == K_EXPIRES) {
        vto = V_TEXT;
        outs("expires=");
        for (i = 0; nb[i] >= '0' && nb[i] <= '9'; ++i)
            out(nb[i]);
        out('\n');
        vto = V_NONE;
        return;
    }
    if (jd < 2 || (jk[jd - 1] == K_ITD && k == K_CACHED)) {
        if (jd < 2)
            return;
    } else if (jk[jd - 1] != K_USAGE || (k != K_IN && k != K_OUT))
        return;
    for (i = 0; nb[i] >= '0' && nb[i] <= '9'; ++i)
        v = v * 10 + nb[i] - '0';
    if (k == K_CACHED)
        p_cache = v;        /* (usage.input_tokens_details.cached_tokens: V123) */
    else if (k == K_IN)
        p_in = v;
    else
        p_out = v;
}

/* a data line ended: its event */
static void event(void)
{
    if (!strcmp(evtype, "response.completed"))
        p_ok = p_end = 1;
    else if (!strcmp(evtype, "response.incomplete"))
        p_inc = p_end = 1;
    else if (!strcmp(evtype, "response.failed"))
        p_errev = p_end = 1;
    else if (!strcmp(evtype, "error"))
        p_errev = 1;
}
