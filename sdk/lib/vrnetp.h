/* vrnet's insides that vrahead.c shares (DECISIONS V210; vrnet.c is
   the rest). Not for applications: vrnet.h is theirs. MIT licence (see
   LICENSE). */
#ifndef VRNETP_H
#define VRNETP_H

#define XON     0x11
#define PKT     254             /* ATS40 */
#define RXSZ    1024            /* a socket's receive ring */

struct sock {
    unsigned char st, id;
    signed char err;
    unsigned int port;
    unsigned int rxh, rxt;      /* the receive ring (RXSZ) */
    unsigned char txh, txt;     /* the send ring (256) */
};

/* (their names in the library, not to clash with a program's) */
#define sk       net__sk
#define orphan   net__orphan
#define hold     net__hold
#define draining net__draining
#define nxt      net__nxt
#define ot       net__ot
#define olen     net__olen
extern struct sock sk[NET_SOCKS];
extern unsigned char orphan, hold, draining, nxt;
extern unsigned int ot;         /* the operation's start (ser_frames): its deadline counts from it */
extern unsigned int olen;       /* (V213) its deadline, in frames */
extern void (*net__ahead)(void);

#endif
