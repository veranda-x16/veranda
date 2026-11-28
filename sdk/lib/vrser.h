/* vrser: a 16C550 UART on the expansion bus, polled from the interrupt,
   for Veranda applications (lib/veranda.lib; DECISIONS V98). Veranda
   Term's driver (V41, V91, V94), shared: Term and vrnet (vrnet.h) link
   it. MIT licence.

   The interrupt half, SerIrq (vrser.s), is the program's intFirstVector:
   it reads the UART from VERA's line interrupt, 8 times a frame (16 with
   ser_fast), into an 8 KB receive ring at $A000 of RAM bank ser_rxbank,
   and sends from a 256-byte transmit ring. The UART's own interrupt is
   off unless ser_open is asked for it. ser_frames counts the frames
   (60 a second) while SerIrq is installed: the timers' clock.

   A program using it directly:
       ser_rxbank = BankAlloc(1);
       intFirstVector = VR_FN(SerIrq);
       asideVector = VR_FN(ser_aside);    (the switcher: V91)
       ser_open(0xE0, ser_div(SER_X14, 576), 0);   (57600 baud, $9FE0)
   then from appMain: ser_wake() first, ser_get() and ser_byte(); before
   it quits: ser_stop(), intFirstVector = 0. Around a desk accessory
   (GetFile): ser_pause(), ser_resume(). */
#ifndef VRSER_H
#define VRSER_H

/* the interrupt half (vrser.s) */
void SerIrq(void);
extern volatile unsigned char ser_on;           /* 0 off, 1 the 16C550, 2 the script */
extern volatile unsigned char ser_lo;           /* the UART's address: $9F00 + ser_lo */
extern volatile unsigned char ser_rxbank;       /* the receive ring's RAM bank (8 KB) */
extern volatile unsigned char ser_mcr, ser_ier, ser_flow;
extern volatile unsigned char ser_fast;         /* 1: 16 polls a frame (before ser_open) */
extern volatile unsigned int ser_rxhead, ser_rxtail;
extern volatile unsigned int ser_lost;          /* bytes lost: the ring was full */
extern volatile unsigned int ser_oe;            /* overruns the chip reported */
extern volatile unsigned int ser_frames;        /* frames, while SerIrq is installed */
/* (V213) ser_frames read whole (the interrupt can come between the two
   bytes of a C read of it, as its low byte carries: 256 frames late) */
unsigned int ser_now(void);
extern volatile unsigned int ser_polls;
extern volatile unsigned char ser_txbuf[256];
extern volatile unsigned char ser_txhead, ser_txtail;
/* the script back-end (gates): ser_send bytes from $A000 of bank ser_sbank
   on (across banks), ser_rate a frame; what is sent into ser_logbank */
extern volatile unsigned char ser_sbank, ser_rate, ser_logbank;
extern volatile unsigned int ser_saddr, ser_send, ser_logpos;

/* the crystal, in Hz / 1600 (ser_div's unit): TexElec's Serial & ESP32
   Network Card has 14.7456 MHz (V91), PC-style cards 1.8432 */
#define SER_X14 9216
#define SER_X1  1152

/* the divisor for baud / 100 (576: 57600) at crystal x (Hz / 1600) */
unsigned int __fastcall__ ser_div(unsigned int x, unsigned int baud100);
/* 1 if a 16C550's scratch register answers at $9F00 + lo */
unsigned char __fastcall__ ser_at(unsigned char lo);
/* the first UART in $9F60-$9FF0 by $10 (TexElec's card's DIP switches;
   its DE9 port is 8 above), or 0 */
unsigned char ser_probe(void);
/* the 16C550 at $9F00 + lo, 8N1 at divisor d, FIFOs on, DTR RTS OUT2;
   ier: its own interrupt (0: polled only, the default on TexElec's card,
   V94; 5: receive data and line status); the rings emptied; 0 ok, 1 no
   UART answers there */
unsigned char __fastcall__ ser_open(unsigned char lo, unsigned int d, unsigned char ier);
/* the script back-end instead (ser_on 2) */
void ser_script(void);
/* the divisor changed (the FIFOs cleared; IER kept) */
void __fastcall__ ser_setdiv(unsigned int d);
void ser_stop(void);            /* off, DTR down */
void ser_pause(void);           /* around a desk accessory: no interrupts, RTS down */
void ser_resume(void);
/* the switcher (asideVector, V91): as ser_pause; the main loop's
   ser_wake arms the port again and returns 1 when it did */
void ser_aside(void);
unsigned char ser_wake(void);
extern unsigned char ser_asleep;
unsigned char ser_msr(void);
/* up to max received bytes into buf (below $A000); the RAM bank kept */
unsigned int __fastcall__ ser_get(unsigned char *buf, unsigned int max);
/* a byte to send (waits while the ring is full) */
void __fastcall__ ser_byte(unsigned char c);
unsigned char ser_txroom(void);
/* 1: everything sent (the ring and the chip: LSR's TEMT) */
unsigned char ser_sent(void);

/* the modem's rate (vrsync.c; after Packet16, DECISIONS V94): Zimodem
   keeps the rate it was left at until it is powered off. "AT" at 115200,
   57600, 38400, 19200 and 9600 (0.5 s each) until "OK" or "ERROR"; at
   another rate than want, "ATB<want>" (the modem answers at the new
   rate) and the UART follows once the command has left the chip.
   x: the crystal (Hz / 1600), want: baud / 100. The caller reads the
   modem's lines and hands ser_sync_tick what it saw since the last call
   (0 nothing, 1 OK, 2 ERROR); each pass of its main loop. */
void __fastcall__ ser_sync(unsigned int x, unsigned int want);
/* 0 still looking; 1 the modem answered (at want now); 2 nothing
   answered (the UART at want) */
unsigned char __fastcall__ ser_sync_tick(unsigned char reply);
extern unsigned char ser_sync_new;      /* set at each new try: start the line reader afresh */
extern unsigned int ser_sync_found;     /* the rate that answered (/ 100), 0 none */

#endif
