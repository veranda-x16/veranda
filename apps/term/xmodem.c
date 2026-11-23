/* Veranda Term: XMODEM download (MIT licence, see LICENSE).

   The receiver asks for CRC mode ('C', three times, 3 s apart), then
   falls back to the checksum (NAK); it takes 128-byte (SOH) and 1 KB (STX)
   blocks in either mode, so XMODEM, XMODEM-CRC and XMODEM-1K senders all
   work. Each good block goes straight to the file (FWrite), so a file can
   be larger than memory. A block's number must be the next one (the one
   before is a repeat: acknowledged, not written); a bad block, a wrong
   complement or a 1 s gap inside a block gets a NAK, ten in a row cancel.
   The padding: the last block's trailing ^Z ($1A) bytes are not written
   (each block's trailing ^Zs are held back until the next block comes). */
#include <string.h>
#include "term.h"
#include "net.h"

#define SOH 1
#define STX 2
#define EOT 4
#define ACK 6
#define NAK 21
#define CAN 24
#define SUB 26

unsigned char xm_active, xm_result, xm_crc, xm_big;
unsigned long xm_bytes;
unsigned int xm_blocks, xm_retries;

static unsigned char fh;
static unsigned char st;        /* 0 waiting for a block, 1 number, 2 complement, 3 data, 4 check */
static unsigned char blk, nblk, expect, cans, tries, errs;
static unsigned int len, pos, timer;
static unsigned char started;
static unsigned int held;       /* ^Z bytes held back */
static unsigned char chk[2], nchk;
static unsigned char xbank;     /* the block: $A000 of a RAM bank of its own */
#define BUF ((unsigned char *)0xA000)
static unsigned int crc;
static unsigned char sum;
static unsigned char stage[128];

/* CRC-16/XMODEM (polynomial $1021), a byte at a time as they come */
static void crc_byte(unsigned char b)
{
    unsigned char i;
    crc ^= (unsigned int)b << 8;
    for (i = 0; i < 8; ++i)
        crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1;
}

/* n bytes of the block from offset o to the file, through stage[] (a
   pointer handed to the kernel must be below $A000) */
static void out(unsigned int o, unsigned int n)
{
    unsigned char k;
    while (n) {
        k = n > sizeof stage ? sizeof stage : n;
        MAPBANK(xbank);
        memcpy(stage, BUF + o, k);
        FWrite(fh, stage, k);
        o += k;
        n -= k;
    }
}

static void finish(unsigned char r)
{
    if (fh) {
        FClose(fh);
        fh = 0;
    }
    xm_active = 0;
    xm_result = r;
    status();
}

unsigned char xm_start(const char *name)
{
    if (!xbank)
        xbank = BankAlloc(1);
    if (!xbank)
        return 1;
    fh = FOpen((void *)name, 'w');
    if (fh < 2) {
        fh = 0;
        return 1;
    }
    xm_active = 1;
    xm_result = 0;
    xm_crc = 1;
    xm_big = 0;
    xm_bytes = 0;
    xm_blocks = xm_retries = 0;
    held = 0;
    expect = 1;
    st = 0;
    cans = tries = errs = 0;
    started = 0;
    net_send('C');
    timer = ser_frames;
    status();
    return 0;
}

void xm_cancel(void)
{
    unsigned char i;
    if (!xm_active)
        return;
    for (i = 0; i < 4; ++i)
        net_send(CAN);
    finish(2);
}

static void nak(void)
{
    st = 0;
    ++xm_retries;
    if (++errs >= 10) {
        xm_cancel();
        xm_result = 3;
        return;
    }
    net_send(NAK);
    timer = ser_frames;
}

static void block(void)
{
    unsigned int i;
    if ((unsigned char)(blk + nblk) != 255) {
        nak();
        return;
    }
    /* (two plain ifs: cc65 2.19 -O took A for 0 after "x ? a != b : c != d"
       and stored the CRC into errs) */
    if (xm_crc) {
        if (crc != ((unsigned int)chk[0] << 8 | chk[1])) {
            nak();
            return;
        }
    } else if (sum != chk[0]) {
        nak();
        return;
    }
    errs = 0;
    if (blk == expect) {
        /* the ^Zs held from the block before were data after all */
        if (held) {
            static unsigned char z[64];
            memset(z, SUB, sizeof z);
            while (held) {
                i = held > sizeof z ? sizeof z : held;
                FWrite(fh, z, i);
                xm_bytes += i;
                held -= i;
            }
        }
        MAPBANK(xbank);
        for (i = len; i && BUF[i - 1] == SUB; --i)
            ;
        held = len - i;
        out(0, i);
        xm_bytes += i;
        ++xm_blocks;
        ++expect;
        net_send(ACK);
    } else if (blk == (unsigned char)(expect - 1))
        net_send(ACK);          /* a repeat */
    else {
        xm_cancel();
        xm_result = 3;
        return;
    }
    st = 0;
    timer = ser_frames;
}

void xm_byte(unsigned char c)
{
    timer = ser_frames;
    switch (st) {
    case 0:
        if (c == SOH || c == STX) {
            len = c == SOH ? 128 : 1024;
            if (c == STX)
                xm_big = 1;
            started = 1;
            cans = 0;
            st = 1;
        } else if (c == EOT) {
            net_send(ACK);
            finish(1);          /* the ^Zs held are the padding */
        } else if (c == CAN) {
            if (++cans >= 2)
                finish(2);
        }
        break;
    case 1: blk = c; st = 2; break;
    case 2: nblk = c; st = 3; pos = 0; crc = 0; sum = 0; break;
    case 3:
        MAPBANK(xbank);
        BUF[pos++] = c;
        sum += c;
        if (xm_crc)
            crc_byte(c);
        if (pos == len) {
            st = 4;
            nchk = 0;
        }
        break;
    case 4:
        chk[nchk++] = c;
        if (nchk == (xm_crc ? 2 : 1))
            block();
        break;
    }
}

void xm_tick(void)
{
    unsigned int t = ser_frames - timer;
    if (!xm_active)
        return;
    if (!started) {
        if (t > 180) {          /* 3 s: ask again; CRC three times, then the checksum */
            timer = ser_frames;
            if (++tries == 3)
                xm_crc = 0;
            if (tries > 12) {
                xm_cancel();
                xm_result = 3;
                return;
            }
            net_send(xm_crc ? 'C' : NAK);
        }
    } else if (st && t > 60)    /* 1 s inside a block */
        nak();
    else if (!st && t > 600) {  /* 10 s with nothing */
        nak();
    }
}
