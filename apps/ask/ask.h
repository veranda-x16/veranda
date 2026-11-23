/* Veranda Ask: what its own parts add to apps/claude/claude.h (included
   there with -DASK; DECISIONS V116).

   Veranda Ask builds from Veranda Claude's files (apps/claude: main.c,
   copy.s, store.c, net.c, ui.c, prefs.c, parse.c, with -DASK) and its
   own:
     tok.c    main RAM: the two RAM banks of the credentials, bytes in and
              out of any bank (bk_get, bk_put)
     pick.c   overlay 3 (in parse.c): the values the replies are read for
     turn.c   overlay 2: a turn's end (OpenAI's errors, the plan's codes,
              the sign-in renewed and the turn sent again)
     page.c   overlay 4: the Settings page, the plan's notice, the
              toolbar's and the status bar's texts, the first notes
     auth.c   overlay 5: ASK.CFG (read, written safely), the lines
              key=value (the file, the token endpoint's reply made lines,
              the sign-in helper's reply), the requests laid out (a turn,
              the renewal, the sign-in), the clock's minutes

   MIT licence (see LICENSE). */
#ifndef ASK_H
#define ASK_H

/*--------------------------------------------------------------- the requests (net.c) */
#define RQ_CHAT    0            /* POST /v1/responses (SSE) */
#define RQ_REFRESH 1            /* POST /api/accounts/oauth/token (grant_type=refresh_token) */
#define RQ_SIGNIN  2            /* POST /x16/signin to the PC's helper (tools/chatgpt_signin.py) */
extern unsigned char rq;
extern unsigned char t_cancel;  /* Esc while the sign-in is renewed: the turn ends after it */
extern unsigned char tgo;       /* ask_go: a request started */

/* a request is a list of parts: n bytes at a in bank (0: main RAM), as
   they are (P_RAW), JSON-escaped or URL-encoded; n PZ: a main RAM string
   to its 0; bank PB_MSGS: the conversation's messages ({"role", "content"}
   objects, comma separated, then "]") */
struct part {
    unsigned char bank, fl;
    unsigned int a, n;
};
#define NPARTS  24
#define P_RAW   0
#define P_JSON  1
#define P_URL   2
#define PB_MSGS 0xFF
#define PZ      0xFFFF
extern struct part parts[NPARTS];
extern unsigned char nparts, pbody;     /* the parts; the body's first */
extern char hport[8], hlen_s[8];        /* ":port" (not 443, 80), the body's length */

/* the parser's extras (parse.c, pick.c) */
extern unsigned char p_ok;      /* response.completed came */
extern unsigned char p_jok;     /* (V129) the body's JSON came to its end */
extern unsigned char p_gz;      /* (V129) Content-Encoding other than identity */
extern unsigned long p_body;    /* (V129) the body's bytes (chunks' sizes and CR LFs not counted) */
extern unsigned char p_inc;     /* response.incomplete came (its reason in p_stop) */
extern char p_param[24];        /* error.param */

/*--------------------------------------------------------------- the credentials (tok.c) */
/* Two RAM banks, two slots: the live one (tbank + tlive) and the one a
   sign-in or a renewal fills; kept only when it is whole (the slots
   swapped: tlive ^= 1), so a cut reply never spoils the tokens in use.
   A slot's bank: */
#define TB_ACC   0x0000         /* the access token (5120: V129, was 4096) */
#define TB_REF   0x1400         /* the refresh token (1024: V129, was 2048) */
#define TB_CID   0x1800         /* the client_id issued (oaiapp_...: 128) */
#define TB_HID   0x1880         /* ext_agent_host_id (urn:uuid:...: 64) */
#define TB_LOGIN 0x18C0         /* the account's e-mail (login_hint: 64) */
#define TB_INFO  0x1900         /* struct slot */
#define TB_MOD   0x1940         /* the plan's models: NMOD x 64 (the slug 32, the name 32) */
#define NMOD     8
/* only in the first bank (tbank): */
#define TB_KEY   0x1B40         /* the OpenAI API key (256) */
#define TB_SYS   0x1C40         /* the system prompt (instructions: 920) */
#define TB_AMOD  0x1FD8         /* the API key's model (typed: 40) */
#define ACCMAX   5119
#define REFMAX   1023
#define CIDMAX   127
#define HIDMAX   63
#define LOGMAX   63
#define KEYMAX2  255
#define SYSMAX2  919
struct slot {
    unsigned int acc, ref;      /* the tokens' lengths */
    unsigned char cid, hid, login, nmod;
    unsigned int expires;       /* expires_in (seconds) */
    unsigned long got;          /* when they came: minutes since 2000 (the X16's clock; 0: not known) */
};
extern unsigned char tbank, tlive;
extern unsigned int klen, slen; /* (tbank's) the API key's, the system prompt's lengths */
unsigned char tok_start(void);
/* n bytes of bank b at a into buf (main RAM), and back; b 0: a is in main RAM */
void __fastcall__ bk_get(unsigned char b, unsigned int a, void *buf, unsigned int n);
void __fastcall__ bk_put(unsigned char b, unsigned int a, const void *buf, unsigned int n);
unsigned int __fastcall__ bk_sum(unsigned char b, unsigned int a, unsigned int n);   /* (V131: b a bank) */

/*--------------------------------------------------------------- overlay 5 (auth.c) */
void __fastcall__ ov5(void (*f)(void));
extern unsigned char bLog;      /* (V129) overlay 10: log.c's lg_save (and the test build's tests/ask_play.c) */
void __fastcall__ ovl(void (*f)(void));
void ask_go(void);              /* send's: the turn (or the renewal first); tgo */
void ask_renew(void);           /* turn.c's: the renewal, then the turn again */
void ask_again(void);           /* turn.c's: the turn sent again (after the renewal) */
void ask_signin(void);          /* page.c's: the sign-in through the PC (sg_code) */
void ask_commit(void);          /* turn.c's: the slot filled is kept (ASK.CFG written first) */
void ask_forget(void);          /* turn.c's: the plan's tokens dropped (a terminal renewal error) */
void ask_whole(void);           /* turn.c's: tgo 1 when the slot filled has its tokens (and a client_id);
                                   a renewal's: its access or refresh token came whole (r_why) */
void kv_reply(void);            /* net.c's: dtext[0 .. dn) lines into the slot filled */
void a_load(void), a_save(void);
void ask_models(void);          /* C.mslug, C.mname from the live slot's row C.model */
extern unsigned char kv_ok;     /* the helper's reply said end=ok (its error= in p_emsg) */
extern char sg_code[8];         /* (main RAM) the code the helper showed */
extern char sg_addr[HOSTMAX + 8];       /* the helper's address (host:port) */
extern unsigned char t_retry;   /* the turn was sent again once (after a 401) */
extern unsigned char notice;    /* the plan's notice was seen */
extern unsigned char sv_fail;   /* ASK.CFG could not be written (the last time) */
extern struct slot sl;          /* the live slot's (a copy in main RAM) */
extern unsigned char kv_ovf;    /* (V129) a value longer than its room: which (W_ACC 1, W_REF 2) */
extern unsigned char r_why;     /* (V129) ask_whole's: why a renewal's reply is not (all) kept: */
#define R_ACCLONG 1             /*   its access_token longer than ACCMAX (fatal) */
#define R_NOACC   2             /*   no access_token in it (fatal) */
#define R_CUT     3             /*   cut before its access_token ended (fatal) */
#define R_GZ      4             /*   compressed (fatal) */
#define R_REFLONG 5             /*   its refresh_token too long: the old one kept */
#define R_REFCUT  6             /*   cut after the access token: the old refresh token kept */
#define R_NOREF   7             /*   no refresh_token (not rotated): the old one kept */
extern unsigned long t_exp;     /* (V129) page.c's tok_exp: the access token's exp (Unix seconds; 0: none) */

/*--------------------------------------------------------------- the log (V129: tok.c, log.c) */
/* ASK.LOG in /VERANDA/.SYSTEM: the last renewal (or sign-in) and the last
   turn, no secrets. A request's lines are made in the second credentials
   bank above its slot (LG0, LGMAX bytes; a 401's turn and the renewal it
   asks for together: lg_keep); a renewal's are kept, when it ends, in the
   slot not in use (its access token's room) for the next turn's file. */
#define LG0      0x1B40
#define LGMAX    1216
extern unsigned char lg_keep, lg_tkn, lg_tkx, lg_clkbad;
extern unsigned int lg_n;
extern unsigned char lg_rb;     /* the renewal's log kept in this bank (0: none) */
extern unsigned int lg_rn;      /* its length */
void __fastcall__ lg_c(unsigned char c);
void __fastcall__ lg_s(const char *s);  /* (s in main RAM or the caller's bank) */
void __fastcall__ lg_u(unsigned long v);
void lg_save(void);             /* log.c's (overlay 9): the lines made, ASK.LOG written */
void tok_exp(void);             /* logclk.c's (overlay 4) */
void tok_due(void), clk_check(void);    /* logclk.c's (overlay 10): t_due */
extern unsigned char t_due;
unsigned long now_min(void);    /* tok.c's: the X16's clock, minutes since 2000 (0: not set, or before 2026) */
void lg_red(void);              /* log.c's (overlay 9): an error's body's byte lg_ch into the log, tokens cut */
extern unsigned char lg_ch;
/* (V131) the request's own lines first (logq.c, overlay 6: p_begin's): its
   line, Host, the secret's length and byte sum (never its value: the
   Authorization's token, the renewal's refresh token, parts[lg_ap]), the
   body's length; a 401's turn kept for its renewal cut to LGKEEP, its
   body's lines (from lg_b) kept whole. tok.c's lg_hdr: a header line */
void lg_req0(void), lg_req(void);
void __fastcall__ lg_hdr(const char *h, unsigned char n);
extern unsigned int lg_b, lg_h0;
extern unsigned char lg_ap, lg_hcut;
extern unsigned char t_ok;      /* (V131) tok_due's: the clock is trusted and the token has an exp */
void lg_why(void);              /* log.c's (overlay 8): why a renewal was not (all) kept, into r_txt */
extern char r_txt[52];

/*--------------------------------------------------------------- overlay 4 (page.c) */
void ask_right(void);           /* the status bar's right (ui.c's right) */
void ask_bar(void);             /* the toolbar's model, the plan's line */
void notice_show(void);         /* the plan's first-time notice ("Got it") */
void sys_fill(void);            /* the built-in system prompt into its bank */
extern char right[64];

#endif
