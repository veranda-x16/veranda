/* Veranda Term: the serial port, Telnet, the modem, XMODEM (MIT licence) */
#ifndef NET_H
#define NET_H

/* the serial driver: the SDK's (V98) */
#include <vrser.h>
unsigned int ser_divisor(void);         /* settings/B at settings/X */
unsigned char ser_start(void);          /* 0 ok, 1 no UART at cfg.port */
void term_aside(void);                  /* asideVector (V91) */
void term_wake(void);                   /* the main loop: armed again after it */

extern unsigned char tn_on, tn_echo, tn_bin, tn_seen, tn_auto;
void net_send(unsigned char c);         /* a byte to the host (IAC doubled) */
void net_rx(const unsigned char *p, unsigned int n);
void net_dial(const char *s);
void net_hangup(void);
void net_tick(void);
extern unsigned char syncing;           /* (V94) the modem's rate looked for: */
void o_sync(void);                      /* sync.c (overlay 2): from the start */
unsigned char o_sync_tick(void);        /* each pass of the main loop meanwhile: 1 done */
void dial_go(void);
void sends(const char *s);
extern unsigned char net_mlen;
extern unsigned char term_ovl2;         /* term.c: overlay 2's bank */
void net_dropped(void);                 /* term.c: the line was lost */
extern unsigned char online, dialing, hangup_state, got_ok;
extern unsigned int online_since;
extern unsigned long rx_total;

struct when { unsigned char yr, mon, dy, hr, mn, sec; };
extern struct when net_time;
extern unsigned char net_time_ok;
unsigned char parse_time(const char *s, struct when *w);
void time_zone(struct when *w, signed char quarters);
unsigned char weekday(const struct when *w);
void o_clock_offer(void);               /* sync.c (overlay 2, V112) */
void o_info_pump(void);                 /* sync.c: modem status */
extern unsigned char info_on;           /* term.c */
char *o_fmt_when(char *p, unsigned char y, unsigned char mo, unsigned char d,
                 unsigned char h, unsigned char mi, unsigned char s);

/* (V112) a TCP session through the modem's command mode (tcp.c, in
   overlay 2; term.c maps it and calls o_tcp_poll each pass): tcp is its
   step, 0 none */
#define TCP_WAIT    1           /* the modem's rate still looked for */
#define TCP_SETUP   2           /* the profile (ATE0 ... ATF3) */
#define TCP_DIAL    3           /* ATC"host:port" sent */
#define TCP_OPEN    4
#define TCP_HANGUP  5           /* ATH<id> */
#define TCP_RESET   6           /* ATZ: the modem's own saved profile again */
/* tcp_ev, what happened (term.c shows it, then 0) */
#define TEV_OPEN    1
#define TEV_REFUSED 2
#define TEV_NOMODEM 3
#define TEV_TIMEOUT 4
#define TEV_CLOSED  5           /* by the host */
#define TEV_LOST    6           /* the modem stopped answering */
#define TEV_ENDED   7           /* Disconnect: done */
#define TEV_IDLE    8           /* the modem in its own profile again (ATZ done) */
#define TCP_TXSZ    64
extern unsigned char tcp, tcp_ev, tcp_raw, tcp_quit;
extern unsigned char tcp_tx[TCP_TXSZ], tcp_txh, tcp_txt;
extern char target[48];         /* host:port */
void tx_put(unsigned char c);   /* to the host as it is (the line, or the ring) */
unsigned char tx_room(void);
void tn_reset(unsigned char on);
unsigned char o_tcp_poll(void); /* tcp.c: a packet's bytes into rxbuf: their count */
void o_tcp_start(unsigned char nocard);
void o_tcp_event(void);         /* tcp.c: tcp_ev shown (the log, the status line, a box) */
/* hosts.c (overlay 2): the Hosts page (TERM.HOSTS) */
void o_hosts_draw(void);
unsigned char o_hosts_key(unsigned char k);     /* 1 close, 2 connect */
void o_about(void);
extern char msga[48], msgb[48]; /* term.c: a box's two lines */
void msg_box(void);             /* term.c: msga and msgb in a box */

/* term.c: the capture file */
void capture_byte(unsigned char c);

/* xmodem.c */
extern unsigned char xm_active;
unsigned char xm_start(const char *name);      /* 0 ok, else a file error */
void xm_byte(unsigned char c);
void xm_tick(void);
void xm_cancel(void);
extern unsigned long xm_bytes;
extern unsigned int xm_blocks, xm_retries;
extern unsigned char xm_result;         /* 0 running, 1 done, 2 cancelled, 3 failed */
extern unsigned char xm_crc, xm_big;    /* the mode used: CRC, a 1 KB block seen */

#endif
