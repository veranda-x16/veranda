/* tests/audio/main.c -- gate audio (tools/gate_audio.sh): PCM fed from the
   AFLOW interrupt through intFirstVector (DECISIONS V52) while Veranda
   draws and reads files; then an accessory opened while it plays (K2), then
   a quit with AFLOW still on (K3). BURN: cycles of fake mixing a frame.
   -DSOUND (gate sound, DECISIONS V69): a system sound started every 40
   frames while it plays, from the interrupt; "AUD sounds" the requests,
   "AUD psg_frames" the frames voice 15 sounded.
   Lines "AUD name decimal" on the console. */
#include <veranda.h>
#include <vr.h>
#define C0 (*(volatile unsigned char *)0x9FB8)
#define C1 (*(volatile unsigned char *)0x9FB9)
#define C2 (*(volatile unsigned char *)0x9FBA)
#define C3 (*(volatile unsigned char *)0x9FBB)
#define IEN (*(volatile unsigned char *)0x9F26)
extern void aud_install(void);
extern void aud_arm(void);
extern void aud_disarm(void);
extern volatile unsigned int aud_under, aud_batches;
extern volatile unsigned long aud_frames;
extern unsigned char burn;
static unsigned long cyc(void)
{ unsigned long v; v = C0; v |= (unsigned long)C1 << 8; v |= (unsigned long)C2 << 16; v |= (unsigned long)C3 << 24; return v; }
static char line[64]; static char *hp;
static void put(const char *s) { while (*s) *hp++ = *s++; }
static void dec(unsigned long v)
{ char b[12]; unsigned char n = 0; do { b[n++] = '0' + (char)(v % 10); v /= 10; } while (v); while (n) *hp++ = b[--n]; }
static void say(const char *tag, unsigned long v)
{ hp = line; put("AUD "); put(tag); put(" "); dec(v); *hp = 0; LogText(line); }
static volatile unsigned int vs;
static void tick(void) { ++vs; }
#ifdef SOUND
static unsigned char sf, sid;
static unsigned int nsnd, psgf;
static void stick(void)
{
    *(volatile unsigned char *)0x9F25 = 0;
    *(volatile unsigned char *)0x9F20 = 0xFE;   /* voice 15's volume ($1F9FE) */
    *(volatile unsigned char *)0x9F21 = 0xF9;
    *(volatile unsigned char *)0x9F22 = 0x01;
    if (*(volatile unsigned char *)0x9F23 & 63)
        ++psgf;
    if (++sf == 40) {
        sf = 0;
        if (++sid > 10)
            sid = 1;
        PlaySound(sid);
        ++nsnd;
    }
}
#endif
static char txt[81];
static unsigned char buf[1024];

static unsigned long fill(void) { C0 = 0; SetPattern(2); WRectangle(0, 0, 639, 479); return cyc(); }
static unsigned long copy(void) { C0 = 0; CopyRect(0, 80, 0, 240, 0, 240); return cyc(); }
static unsigned long cards(void)
{ unsigned char r; C0 = 0; for (r = 0; r < 60; ++r) PutCards(txt, (void *)0x0801, 0, 80, r * 8, 0); return cyc(); }
static unsigned long readf(void)
{ unsigned char h; unsigned int n; C0 = 0; h = FOpen("data.bin", 'r'); if (h < 2) return 0;
  do { n = FRead(h, buf, sizeof buf); } while (n == sizeof buf); FClose(h); return cyc(); }
static unsigned long wait(unsigned long c) { unsigned long w; C0 = 0; do { w = cyc(); } while (w < c); return w; }

static void run(const char *tag)
{
    hp = line; put("AUD "); put(tag); *hp = 0; LogText(line);
    say("fill_cyc", fill());
    say("copy_cyc", copy());
    say("cards_cyc", cards());
    say("read64k_cyc", readf());
}

int main(void)
{
    unsigned char i, r;
    unsigned int b0;
    for (i = 0; i < 80; ++i) txt[i] = 'A' + (i & 15);
    burn = BURN;
    say("burn", burn);
    run("quiet");
    aud_install();
    wait(2000000ul);
#ifdef SOUND
    vr_set_irq(stick);
#endif
    run("playing");
#ifdef SOUND
    wait(8000000ul);
    vr_set_irq(0);
    say("sounds", nsnd);
    say("psg_frames", psgf);
#endif
    /* the frame interrupt goes on: VSYNCs counted over 8 M cycles */
    { unsigned long w;
      C0 = 0; vs = 0; vr_set_irq(tick);   /* (the wait may end a batch late) */
      w = wait(8000000ul);
      vr_set_irq(0);
      say("vsyncs", vs);
      say("vsync_cycles", w); }
    say("frames_out", aud_frames);
    say("batches", aud_batches);
    say("underruns", aud_under);
    /* an accessory while it plays (K2): it logs IEN and comes back */
    b0 = aud_batches;
    r = GetFile("AudDA", 0, 0, 0, 0);
    say("da_ret", r);
    say("da_ien_after", IEN & 8);
    aud_install();                  /* (RstrAppl cleared intFirstVector) */
    wait(4000000ul);
    say("da_batches_after", aud_batches - b0);
    say("da_underruns", aud_under);
    /* a quit with AFLOW on and the routine set (K3) */
    LogText("AUD QUIT");
    EnterDeskTop();
    return 0;
}
