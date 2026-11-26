/*
 * main.c -- MIDI Player's main RAM part (mp.h says what is where): the
 * start, the folder's entries, a song loaded into RAM banks and played,
 * everything that maps another RAM bank.
 *
 * A song is read whole into RAM banks from BankAlloc (one run of banks:
 * both engines read on from bank to bank), up to what the free banks hold.
 * MIDI: Melodius's engine (format 0 and 1, up to 32 tracks); ZSM: ZSMKit.
 * Both tick in the interrupt (engine.s), so menus, boxes and redrawing do
 * not stop the music; Alt+Tab pauses it (Veranda calls nothing of a
 * program put aside), and it goes on when the program comes back.
 *
 * The folder's entries in RAM banks, the sort and the folder walk follow
 * the MOD Player's (x16-mod, examples/veranda/vmodplay.c: MIT, Copyright
 * (c) 2026 Marcin Spoczynski).
 *
 * Started by the shell with a song (app.hdr's documents = MID MIDI ZSM):
 * r0L & ST_LD_DATA, its name in dataLongName, its folder in curDirName.
 *
 * MIT licence (see LICENSE).
 */
#include "mp.h"

char sb[80];

/*---------------------------------------------------------------
  the folder: its entries in 2 RAM banks, 64 bytes each: type, name
 ---------------------------------------------------------------*/
#define ENT_BANKS  2
static unsigned char ent_bank;
unsigned char n_ent, top, sel, n_songs;
static unsigned char ent[3 + 64];       /* DirNext's entry */
char cur[64];
static unsigned char order[ENT_MAX];    /* the entries sorted: their slots */

static char *slot(unsigned char i)      /* (maps its bank: put the caller's back) */
{
    MAPBANK((unsigned char)(ent_bank + (i >> 7)));
    return (char *)(0xA000 + ((unsigned int)(i & 127) << 6));
}

void ent_get(unsigned char i)
{
    unsigned char save = BANK;
    memcpy(cur, slot(order[i]), 64);
    MAPBANK(save);
}

static void ent_put(unsigned char type, const char *name)
{
    unsigned char save = BANK;
    char *p = slot(n_ent);
    order[n_ent] = n_ent;
    p[0] = type;
    strncpy(p + 1, name, 62);
    p[63] = 0;
    MAPBANK(save);
    ++n_ent;
}

static unsigned char lower(unsigned char c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }

/* E_MIDI for "x.mid", "x.midi", E_ZSM for "x.zsm", else 0 */
static unsigned char song_type(const char *s)
{
    unsigned char l = (unsigned char)strlen(s), i;
    char e[6];
    for (i = l; i && s[i - 1] != '.'; --i)
        ;
    if (!i || l - i > 4)
        return 0;
    for (l = 0; s[i] && l < 5; ++i)
        e[l++] = lower(s[i]);
    e[l] = 0;
    if (!strcmp(e, "mid") || !strcmp(e, "midi"))
        return E_MIDI;
    if (!strcmp(e, "zsm"))
        return E_ZSM;
    return 0;
}

unsigned char at_root(void) { return curDirName[1] == 0; }

static unsigned char rank(char t) { return t == E_UP ? 0 : t == E_DIR ? 1 : 2; }

/* entries a and b (slots) in order: "..", folders, songs; then the name
   without regard to case */
static signed char ent_cmp(unsigned char a, unsigned char b)
{
    unsigned char save = BANK, i, x, y;
    signed char r = 0;
    const char *q;
    memcpy(cur, slot(a), 64);
    q = slot(b);
    x = rank(cur[0]);
    y = rank(q[0]);
    if (x != y)
        r = x < y ? -1 : 1;
    else
        for (i = 1; i < 64; ++i) {
            x = lower(cur[i]);
            y = lower(q[i]);
            if (x != y) { r = x < y ? -1 : 1; break; }
            if (!x) break;
        }
    MAPBANK(save);
    return r;
}

static void list_sort(void)
{
    unsigned char i, j, t;
    for (i = 1; i < n_ent; ++i) {
        t = order[i];
        for (j = i; j && ent_cmp(order[j - 1], t) > 0; --j)
            order[j] = order[j - 1];
        order[j] = t;
    }
}

/* The whole listing is read before any file is opened (on the SD card a
   file opened ends a listing): folders, then songs. */
void list_read(void)
{
    unsigned char pass, t;
    n_ent = 0;
    n_songs = 0;
    if (!at_root())
        ent_put(E_UP, "..");
    for (pass = 0; pass < 2; ++pass) {
        if (DirOpen("*"))
            continue;
        while (DirNext(ent) == 0 && n_ent < ENT_MAX) {
            const char *nm = (const char *)ent + 3;
            if (nm[0] == '.')
                continue;               /* (., .. and hidden folders) */
            if (pass == 0 && ent[0] == 'D')
                ent_put(E_DIR, nm);
            else if (pass == 1 && ent[0] == 'F' && (t = song_type(nm)) != 0) {
                ent_put(strlen(nm) > 62 ? E_LONG : t, nm);
                ++n_songs;
            }
        }
    }
    list_sort();
    top = sel = 0;
}

/* the entry named name (a song), or 0xFF */
unsigned char find_entry(const char *name)
{
    unsigned char i;
    for (i = 0; i < n_ent; ++i) {
        ent_get(i);
        if ((cur[0] == E_MIDI || cur[0] == E_ZSM) && !strcmp(cur + 1, name))
            return i;
    }
    return 0xFF;
}

/*---------------------------------------------------------------
  a song: read whole into a run of RAM banks
 ---------------------------------------------------------------*/
char playing_name[64];
char playing_dir[64];
unsigned char playing_ent = 0xFF;      /* the list entry playing */
unsigned char loaded, paused, kind, volume = 10, repeat, play_next = 1;
unsigned long song_size;
unsigned char err;
unsigned char song_bank;
unsigned char song_no;                  /* (V206) counts the songs started and stopped */
unsigned char hilite;
struct songinfo info;
char gm[24];
unsigned char info_buf[64];             /* (info.c's reader: below $A000) */
unsigned char gm_prog;

static void song_free(void)
{
    if (song_bank) {
        BankFree(song_bank);
        song_bank = 0;
    }
}

/* name into song_bank: 0, else the error */
static unsigned char song_load(const char *name)
{
    unsigned char fh, n, i, save = BANK, e = 0;
    unsigned int got;
    unsigned long left;
    song_free();
    fh = FOpen((void *)name, 'r');
    if (fh < 2)
        return ERR_OPEN;
    FSize(fh);
    song_size = r0 | ((unsigned long)r1 << 16);
    if (song_size < 14)
        e = ERR_EMPTY;
    else if (song_size > 255UL * 8192)
        e = ERR_MEM;
    else {
        n = (unsigned char)((song_size + 8191) >> 13);
        song_bank = BankAlloc(n);
        if (!song_bank)
            e = ERR_MEM;
        else
            for (i = 0, left = song_size; i < n; ++i) {
                MAPBANK((unsigned char)(song_bank + i));
                got = FRead(fh, (void *)0xA000, left > 8192 ? 8192 : (unsigned int)left);
                MAPBANK(save);
                if (!got) {
                    e = ERR_READ;
                    break;
                }
                left -= got;
                if (got < 8192 && left) {       /* (a short read: the rest of the bank) */
                    MAPBANK((unsigned char)(song_bank + i));
                    got = FRead(fh, (void *)(0xA000 + got), 8192 - got);
                    MAPBANK(save);
                    left -= got;
                }
            }
    }
    FClose(fh);
    MAPBANK(save);
    if (e)
        song_free();
    return e;
}

void __fastcall__ song_peek(unsigned char *buf, unsigned char n)
{
    unsigned char b = BANK;
    MAPBANK(song_bank);
    memcpy(buf, (void *)0xA000, n);
    MAPBANK(b);
}

/* stopped: everything silent, the song's banks freed */
void stop(void)
{
    unsigned char b = BANK;
    eng_stop();
    if (loaded)
        ++song_no;
    loaded = 0;
    paused = 0;
    song_free();
    MAPBANK(b);
}

void pause_set(unsigned char p)
{
    if (!loaded || p == paused)
        return;
    paused = p;
    if (p)
        eng_pause();
    else
        eng_go();
}

/* the song again from its start (Repeat) */
void restart(void)
{
    eng_rewind();
    eng_volume(volume);
    eng_go();
}

void set_volume(unsigned char v)
{
    volume = v > 10 ? 10 : v;
    eng_volume(volume);
}

/* load entry e (a song) and start it: 0, else the error (nothing plays
   then) */
unsigned char play_entry(unsigned char e)
{
    unsigned char r, b = BANK;
    ent_get(e);
    if (cur[0] != E_MIDI && cur[0] != E_ZSM)
        return ERR_OPEN;
    strcpy(playing_name, cur + 1);
    kind = cur[0];
    stop();                     /* (nothing plays while a song loads) */
    playing_ent = 0xFF;
    r = song_load(playing_name);
    if (!r) {
        if (kind == E_MIDI)
            r = eng_midi_load(song_bank) ? ERR_MIDI : 0;
        else
            r = eng_zsm_load(song_bank) ? ERR_ZSM : 0;
        if (r)
            song_free();
    }
    MAPBANK(b);
    err = r;
    if (r) {
        LOG("MP ERROR", playing_name);
        return r;
    }
    eng_frames = 0;
    ++song_no;
    memset(midi_msg_sent, 0, 16);      /* (V206: the window's channel marks: the song's own) */
    eng_volume(volume);
    eng_go();
    playing_ent = e;
    loaded = 1;
    paused = 0;
    LOG(kind == E_MIDI ? "MP PLAY MIDI" : "MP PLAY ZSM", playing_name);
    return 0;
}

/* the playlist's folder made the music's again (the folder of the song
   last played or tried): 0 if it is shown, 1 if curDirName changed to it
   (the caller reads the list) */
unsigned char music_dir(void)
{
    if (!playing_dir[0] || !strcmp(playing_dir, (const char *)curDirName))
        return 0;
    if (ChDir((void *)playing_dir)) {
        ChDir((void *)curDirName);      /* (it went: the list stays) */
        return 0;
    }
    strcpy((char *)curDirName, playing_dir);
    return 1;
}

/*---------------------------------------------------------------
  the start
 ---------------------------------------------------------------*/
unsigned char ui_bank, vis_bank, info_bank, now_bank;

/* an overlay record's RAM bank (overlays = banked: run in place there) */
static unsigned char overlay_bank(unsigned char n)
{
    return LoadOverlay(n, 0) == 0 && r0 == 0xA000 ? r1L : 0;
}

int main(void)
{
    unsigned char doc = (unsigned char)(r0L & ST_LD_DATA);     /* (before anything uses r0) */
    unsigned char i;
    static char name[LONG_MAX + 1];

    if (doc)
        strncpy(name, (const char *)dataLongName, LONG_MAX);
    ent_bank = BankAlloc(ENT_BANKS);
    ui_bank = overlay_bank(1);
    zsm_bank = overlay_bank(2);
    vis_bank = overlay_bank(4);
    info_bank = overlay_bank(5);
    now_bank = overlay_bank(6);
    if (!ent_bank || !ui_bank || !zsm_bank || overlay_bank(3) != zsm_bank + 1 || !vis_bank || !info_bank || !now_bank) {
        LogText("MP NO BANKS");
        EnterDeskTop();
    }
    appBank = ui_bank;
    MAPBANK(ui_bank);
    eng_init();
    eng_irq_on();
    /* (the folder in curDirName made the current one, so that the two
       agree: started from the dock the DOS's current folder need not be
       curDirName's, and an empty or unknown one is the card's top) */
    if (!curDirName[0] || curDirName[0] != '/' || ChDir((void *)curDirName)) {
        curDirName[0] = '/';
        curDirName[1] = 0;
        ChDir("/");
    }
    /* (started from the dock or /VERANDA: the user's documents instead) */
    if (!doc && !memcmp((const char *)curDirName, "/VERANDA", 8) && !ChDir("/DOCUMENTS"))
        strcpy((char *)curDirName, "/DOCUMENTS");
    list_read();
    ui_start();
    LogText("MP RUNNING");
    if (doc) {
        i = find_entry(name);
        LOG("MP DOCUMENT", name);
        if (i != 0xFF)
            ui_play(i);
    }
    return 0;
}
