/* vrser: the serial driver's C half (vrser.h; DECISIONS V98). Veranda
   Term's (net.c's ser_* functions, V41, V91, V94), made independent of
   Term's settings so that Term and vrnet share it. MIT licence (see
   LICENSE), Veranda's own.

   The chip's registers are written by C only outside the interrupt's
   own stores (THR, IER, MCR are written absolutely there: V91); C's
   stores compile to absolute or (zp) addressing, never an indexed
   store's dummy read of RBR. */
#include <veranda.h>
#include "vrser.h"

#define REG(r)  (*(volatile unsigned char *)(0x9F00 + ser_lo + (r)))
#define VERA_IEN  (*(volatile unsigned char *)0x9F26)
#define VERA_LINE (*(volatile unsigned char *)0x9F28)
#define RAMBANK   (*(volatile unsigned char *)0)

unsigned char ser_asleep;

unsigned int __fastcall__ ser_div(unsigned int x, unsigned int b)
{
    unsigned int d = (x + b / 2) / b;
    return d ? d : 1;
}

unsigned char __fastcall__ ser_at(unsigned char lo)
{
    volatile unsigned char *scr = (volatile unsigned char *)(0x9F07 + lo);
    *scr = 0x55;
    if (*scr != 0x55)
        return 0;
    *scr = 0xAA;
    return *scr == 0xAA;
}

/* the card's DIP switches put its first UART (the ESP32's) at one of ten
   16-byte ranges $9F60-$9FF0 (the factory's $9FE0) and the second (the
   DE9 port) 8 above it (V91: TexElec's card, as Packet16 found it) */
unsigned char ser_probe(void)
{
    unsigned char lo = 0x60;
    do {
        if (ser_at(lo))
            return lo;
        lo += 0x10;
    } while (lo);
    return 0;
}

/* the divisor (V94: the modem's rate looked for); the FIFOs cleared;
   IER as it was (DLM, not IER, is written under DLAB) */
void __fastcall__ ser_setdiv(unsigned int d)
{
    asm("sei");                 /* (the poll writes THR: DLL under DLAB) */
    REG(3) = 0x83;
    REG(0) = d;
    REG(1) = d >> 8;
    REG(3) = 0x03;
    REG(2) = 0x87;
    asm("cli");
}

static void lines_on(unsigned char on)
{
    asm("sei");
    if (on) {
        /* the first of vrser.s's grid of lines: 60 (8 a frame, V94) or 30 (16) */
        VERA_LINE = ser_fast ? 30 : 60;
        VERA_IEN = (VERA_IEN & 0x7F) | 0x02;
    } else
        VERA_IEN &= 0x7D;
    asm("cli");
}

static void rings(void)
{
    ser_stop();
    asm("sei");
    ser_rxhead = ser_rxtail = 0;
    ser_txhead = ser_txtail = 0;
    ser_flow = 0;
    asm("cli");
}

void ser_script(void)
{
    rings();
    ser_on = 2;
}

unsigned char __fastcall__ ser_open(unsigned char lo, unsigned int d, unsigned char ier)
{
    rings();
    if (!ser_at(lo))
        return 1;
    ser_lo = lo;
    REG(1) = 0;                 /* no interrupts while it is set up */
    REG(3) = 0x80;              /* the divisor */
    REG(0) = d;
    REG(1) = d >> 8;
    REG(3) = 0x03;              /* 8N1 */
    REG(2) = 0x87;              /* FIFOs on, cleared, receive trigger 8 */
    ser_mcr = 0x0B;             /* DTR, RTS, OUT2 (never AFE: CTS stays low on TexElec's card, V91) */
    REG(4) = ser_mcr;
    /* the chip's own interrupt only when asked: by default the UART never
       interrupts (IER 0, polled from VERA's line interrupt), the set-up
       Packet16 runs on TexElec's card (V94) */
    ser_ier = ier;
    (void)REG(5);
    (void)REG(0);
    (void)REG(6);
    ser_on = 1;
    REG(1) = ser_ier;
    lines_on(1);
    return 0;
}

void ser_stop(void)
{
    if (ser_on == 1) {
        REG(1) = 0;
        REG(4) = 0;             /* DTR down: the modem may hang up */
    }
    ser_on = 0;
    lines_on(0);
}

/* around a desk accessory (the application's memory is put aside, with
   the interrupt routine): no interrupts, RTS down, DTR kept */
void ser_pause(void)
{
    if (ser_on == 1) {
        REG(1) = 0;
        REG(4) = 0x01;
    }
    lines_on(0);
}

void ser_resume(void)
{
    if (ser_on == 1) {
        REG(4) = ser_mcr;
        REG(1) = ser_ier;
        (void)REG(5);
    }
    if (ser_on)
        lines_on(1);
}

/* (V91) the switcher is about to put the program aside or ask whether it
   may quit it (asideVector, from the main loop): the kernel stops calling
   SerIrq next, so the UART's interrupt (on the bus's IRQ line by default,
   a level the chip holds) and VERA's line interrupt go off first, as
   around a desk accessory; the main loop arms them again when the
   program runs again (ser_wake) */
void ser_aside(void)
{
    ser_pause();
    ser_asleep = 1;
}

unsigned char ser_wake(void)
{
    if (!ser_asleep)
        return 0;
    ser_asleep = 0;
    ser_resume();
    return 1;
}

unsigned char ser_msr(void)
{
    return ser_on == 1 ? REG(6) : 0xB0;
}

unsigned int __fastcall__ ser_get(unsigned char *buf, unsigned int max)
{
    unsigned int head, tail = ser_rxtail, n = 0;
    unsigned char *p;
    unsigned char b = RAMBANK;
    asm("sei");
    head = ser_rxhead;
    asm("cli");
    RAMBANK = ser_rxbank;
    while (tail != head && n < max) {
        p = (unsigned char *)0xA000 + tail;
        buf[n++] = *p;
        tail = (tail + 1) & 0x1FFF;
    }
    RAMBANK = b;
    asm("sei");
    ser_rxtail = tail;
    asm("cli");
    return n;
}

void __fastcall__ ser_byte(unsigned char c)
{
    unsigned char h = ser_txhead + 1;
    while (h == ser_txtail)
        if (!ser_on)
            return;             /* (the interrupt empties it) */
    ser_txbuf[ser_txhead] = c;
    ser_txhead = h;
    if (ser_on == 1 && ser_ier) {       /* (V94: else the next poll sends it) */
        asm("sei");
        REG(1) = ser_ier | 0x02;        /* the transmit interrupt */
        asm("cli");
    }
}

unsigned char ser_txroom(void)
{
    return ser_txtail - ser_txhead - 1;
}

unsigned char ser_sent(void)
{
    return ser_txhead == ser_txtail && (ser_on != 1 || (REG(5) & 0x40));
}
