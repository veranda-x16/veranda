/* vrser: the modem's rate (vrser.h's ser_sync; DECISIONS V94, V98).
   Shared by Veranda Term (which compiles this file into a banked overlay
   of its own) and vrnet (from lib/veranda.lib).

   After Packet16 (the X16 FTP client by Marcin Spoczynski: link.c's
   link_open, net_zimodem.c's zn_sync and zn_set_baud), used under the
   MIT licence with its author's permission: Zimodem keeps the rate it
   was left at (115200 on TexElec's card) until it is powered off, and a
   terminal at another rate gets noise and sends noise. "AT" at 115200,
   57600, 38400, 19200 and 9600 until "OK" (or "ERROR") comes back; at
   another rate than the one wanted, "ATB<rate>" moves the modem (it
   answers at the new rate) and the UART follows once the command has
   left the chip. Nothing answers (no modem, or it is online): the UART
   stays at the rate wanted.

   MIT licence (see LICENSE). */
#include "vrser.h"

static const unsigned int sync_try[] = { 1152, 576, 384, 192, 96 };   /* baud / 100 */
static unsigned char sync_i, sync_st;
static unsigned int stimer, sx, swant;
unsigned char ser_sync_new;
unsigned int ser_sync_found;

static void sync_at(void)
{
    ser_setdiv(ser_div(sx, sync_try[sync_i]));
    ser_byte('A');
    ser_byte('T');
    ser_byte(13);
    stimer = ser_frames;
    ser_sync_new = 1;
    sync_st = 1;
}

void __fastcall__ ser_sync(unsigned int x, unsigned int want)
{
    sx = x;
    swant = want;
    sync_i = 0;
    ser_sync_found = 0;
    sync_at();
}

/* "ATB", the rate's digits and two zeros, CR */
static void atb(void)
{
    unsigned int v = swant;
    unsigned char d[5], n = 0;
    ser_byte('A');
    ser_byte('T');
    ser_byte('B');
    do {
        d[n++] = '0' + v % 10;
        v /= 10;
    } while (v);
    while (n)
        ser_byte(d[--n]);
    ser_byte('0');
    ser_byte('0');
    ser_byte(13);
}

unsigned char __fastcall__ ser_sync_tick(unsigned char reply)
{
    unsigned int t = ser_frames;
    if (sync_st == 1) {
        if (reply) {
            ser_sync_found = sync_try[sync_i];
            if (ser_sync_found == swant)
                goto found;
            atb();
            stimer = t;
            sync_st = 2;
        } else if (t - stimer > 30) {
            if (++sync_i < sizeof sync_try / sizeof sync_try[0])
                sync_at();
            else {
                ser_setdiv(ser_div(sx, swant));   /* nothing answered */
                sync_st = 0;
                return 2;
            }
        }
    } else if (sync_st == 2) {          /* ATB has left the chip (TEMT): the new rate */
        if (ser_sent() || t - stimer > 60) {
            ser_setdiv(ser_div(sx, swant));
            stimer = t;
            sync_st = 3;
        }
    } else if (sync_st == 3) {
        if (reply || t - stimer > 60)
            goto found;
    } else
        return 2;
    return 0;
found:
    sync_st = 0;
    return 1;
}
