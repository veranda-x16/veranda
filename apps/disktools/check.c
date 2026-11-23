/* Disk Tools: Check (DECISIONS V119): the card's FAT and folders looked
   at for what can be found cheaply, READ ONLY: nothing is ever written to
   the card and nothing is repaired; it reports.

   Its sectors are read directly (sysui's sd.s: CMD17 through VERA's SPI
   port, as the DOS's own driver reads them; there is no write command in
   that file), after the geometry from the boot sector (card.c).

   1. Every folder from the root down (a stack in RAM banks): its own
      cluster chain first, then its entries (long names put together,
      their checksum checked); each file's chain followed in the first
      FAT: a chain that starts or points past the card's last cluster, a
      cluster marked bad, a chain that runs into a free cluster, a
      cluster already in another chain (a bit a cluster, in RAM banks:
      chains crossing, and a chain that loops), a file whose chain is
      shorter than its size needs or longer, a folder over 2 MB (FAT32's
      most: a loop).
   2. The whole FAT, sector by sector, with the second copy beside it:
      the sectors where the two differ; clusters in use that no file or
      folder reaches (lost), and the free ones, against FSInfo's count.
   A folder or a file is a step of the main loop at most a few sectors
   long, so Esc stops it and the switcher may put Disk Tools aside (the
   check then stops: the card may change meanwhile). Without the RAM for
   the bits (a bank for every 65,536 clusters) crossing and lost clusters
   are not looked for, and it says so. MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "dt.h"
#include "check.h"

#define EOC     0x0FFFFFF8UL
#define BADC    0x0FFFFFF7UL
#define DIRMAX  (0x200000UL >> 9)       /* a folder's most sectors (2 MB) */
#define Y0      (BODY_TOP + 8)

unsigned char st, nobits;
unsigned char bm, nbm, sbank, fbank;     /* bits, the folder stack, the fault lines */
unsigned int nstack, nfault, nshown;
static unsigned long maxc;                      /* the last cluster */
static unsigned char fatbuf[512];
static unsigned long fatlba;

/* the chain being followed */
static unsigned long c_cl, c_n, c_need;
static unsigned char c_dir, c_ok;
static char c_path[64];

/* the folder being read */
static unsigned long d_cl, d_n, d_max;
static unsigned char d_sec, d_ent;
static char d_path[64];

/* counts */
unsigned long n_dirs, n_files, n_lost, n_free, n_fatdiff, s_fat;
unsigned int n_toomany;
static char lfn[64];
static unsigned char lfn_sum, lfn_ok;

/*---------------------------------------------------------------- faults */
static void fault(void)
{
    unsigned char keep = RAMBANK;
    ++nfault;
    dt_log("DT FAULT ", line);
    if (nfault > MAXF)
        return;
    RAMBANK = fbank;
    strncpy((char *)BANKMEM + ((nfault - 1) << 7), line, 127);
    BANKMEM[((nfault - 1) << 7) + 127] = 0;
    RAMBANK = keep;
}

/* line = the chain's path, then s, then the cluster's number */
static void cfault(const char *s, unsigned long c)
{
    char *p;
    strcpy(line, c_path[0] ? c_path : "/");
    strcat(line, s);
    if (c != 0xFFFFFFFFUL) {
        p = line + strlen(line);
        p = ui_num(p, c);
        *p = 0;
    }
    fault();
}

/*---------------------------------------------------------------- the FAT, the bits */
static unsigned long __fastcall__ fat(unsigned long c)
{
    unsigned long l = card.fat_lba + (c >> 7);
    unsigned char *p;
    if (l != fatlba) {
        sd_lba = l;
        sd_buf = fatbuf;
        if (sd_read()) {
            fatlba = 0xFFFFFFFFUL;
            return BADC;
        }
        fatlba = l;
    }
    p = fatbuf + (((unsigned char)c & 127) << 2);
    return le32(p) & 0x0FFFFFFFUL;
}

/* the cluster's bit set; 1 if it was set already */
static unsigned char __fastcall__ mark(unsigned long c)
{
    unsigned char keep = RAMBANK, m = 1 << ((unsigned char)c & 7), r;
    unsigned char *p;
    if (nobits)
        return 0;
    RAMBANK = bm + (unsigned char)(c >> 16);
    p = BANKMEM + (((unsigned int)c & 0xFFFF) >> 3);
    r = *p & m;
    *p |= m;
    RAMBANK = keep;
    return r != 0;
}

/*---------------------------------------------------------------- the folder stack */
static void push(unsigned long cl, const char *path)
{
    unsigned char keep = RAMBANK;
    unsigned char *p;
    if (nstack >= 256) {
        ++n_toomany;
        return;
    }
    RAMBANK = sbank + (nstack >> 7);
    p = BANKMEM + ((nstack & 127) << 6);
    memcpy(p, &cl, 4);
    strncpy((char *)p + 4, path, 59);
    p[63] = 0;
    ++nstack;
    RAMBANK = keep;
}

static unsigned char pop(void)
{
    unsigned char keep = RAMBANK;
    unsigned char *p;
    if (!nstack)
        return 0;
    --nstack;
    RAMBANK = sbank + (nstack >> 7);
    p = BANKMEM + ((nstack & 127) << 6);
    memcpy(&c_cl, p, 4);
    strcpy(c_path, (char *)p + 4);
    RAMBANK = keep;
    return 1;
}

/*---------------------------------------------------------------- chains */
static void chain(unsigned long start, unsigned long need, unsigned char dir)
{
    c_cl = start;
    c_n = 0;
    c_need = need;
    c_dir = dir;
    c_ok = 1;
    st = S_CHAIN;
}

static void next_dir(void);
static void read_dir(void);

static void chain_end(void)
{
    if (c_ok && !c_dir && c_n < c_need) {
        strcpy(line, c_path);
        strcat(line, ": its chain has ");
        ui_num(line + strlen(line), c_n);
        strcat(line, " of the ");
        ui_num(line + strlen(line), c_need);
        strcat(line, " clusters its size needs");
        fault();
    }
    if (c_dir) {
        ++n_dirs;
        read_dir();                     /* (the clusters it had, good or not) */
    } else
        st = S_DIR;                     /* back to its folder's entries */
}

/* up to n clusters of the chain */
static void chain_step(unsigned int n)
{
    unsigned long v, c = c_cl;
    if (c_n == 0 && (c < 2 || c > maxc)) {
        if (c || c_dir || c_need)
            cfault(c ? ": its first cluster is past the end of the card: " : ": it has no cluster (0)", c ? c : 0xFFFFFFFFUL);
        c_ok = 0;
        chain_end();
        return;
    }
    while (n--) {
        if (mark(c)) {
            cfault(": its chain crosses another chain (or itself) at cluster ", c);
            c_ok = 0;
            break;
        }
        ++c_n;
        if (c_dir ? c_n > DIRMAX / card.spc : c_n > c_need && !(c_need == 0 && c_n == 1)) {
            if (c_dir)
                cfault(": the folder's chain goes on past 2 MB (a loop?) at cluster ", c);
            else {
                strcpy(line, c_path);
                strcat(line, ": its chain is longer than its size needs (");
                ui_num(line + strlen(line), c_need);
                strcat(line, c_need == 1 ? " cluster)" : " clusters)");
                fault();
            }
            c_ok = 0;
            break;
        }
        v = fat(c);
        if (v >= EOC) {
            c_cl = c;
            chain_end();
            return;
        }
        if (v == BADC) {
            cfault(": a bad cluster mark (or an unreadable FAT) after cluster ", c);
            c_ok = 0;
            break;
        }
        if (!v) {
            cfault(": its chain runs into a free cluster after cluster ", c);
            c_ok = 0;
            break;
        }
        if (v < 2 || v > maxc) {
            strcpy(line, c_path[0] ? c_path : "/");
            strcat(line, ": its chain points past the end of the card: ");
            ui_hex(line + strlen(line), v, 8);
            fault();
            c_ok = 0;
            break;
        }
        c = v;
    }
    c_cl = c;
    if (!c_ok)
        chain_end();
}

/*---------------------------------------------------------------- folders */
static unsigned long d_first;          /* the folder's first cluster */

/* its entries read next, from its first cluster (d_cl 0), as many
   clusters as its chain had good ones */
static void read_dir(void)
{
    strcpy(d_path, c_path);
    d_max = c_n;
    d_n = 0;
    d_sec = 0;
    d_ent = 0;
    d_cl = 0;
    lfn_ok = 0;
    st = S_DIR;
    if (!d_max)
        next_dir();
}

static void next_dir(void)
{
    if (!pop()) {
        st = S_FAT;
        s_fat = 0;
        return;
    }
    d_first = c_cl;
    chain(c_cl, 0, 1);
}

static unsigned char sum83(const unsigned char *e)
{
    unsigned char s = 0, i;
    for (i = 0; i < 11; ++i)
        s = ((s & 1) << 7) + (s >> 1) + e[i];
    return s;
}

static const unsigned char lfnoff[13] = { 1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30 };

/* an entry's name (its long name if it has a good one) into nm */
static void name83(const unsigned char *e, char *nm)
{
    unsigned char i, n = 0;
    if (lfn_ok && lfn_sum == sum83(e)) {
        strcpy(nm, lfn);
        return;
    }
    for (i = 0; i < 8 && e[i] != ' '; ++i)
        nm[n++] = e[i];
    if (e[8] != ' ') {
        nm[n++] = '.';
        for (i = 8; i < 11 && e[i] != ' '; ++i)
            nm[n++] = e[i];
    }
    nm[n] = 0;
}

static void lfn_part(const unsigned char *e)
{
    unsigned char seq = (e[0] & 0x1F) - 1, i, at;
    unsigned int ch;
    if (e[0] & 0x40) {
        memset(lfn, 0, sizeof lfn);
        lfn_sum = e[13];
        lfn_ok = 1;
    }
    if (!lfn_ok || seq > 4)
        return;                         /* (a name of more than 63: its short one) */
    for (i = 0; i < 13; ++i) {
        at = seq * 13 + i;
        ch = le16(e + lfnoff[i]);
        if (!ch || ch == 0xFFFF)
            break;
        if (at < 63)
            lfn[at] = ch < 128 && ch >= 32 ? ch : '?';
    }
}

/* the folder's entries: up to n sectors; 0 when it is done */
static void dir_step(unsigned char n)
{
    static char nm[64], path[64];
    unsigned char *e;
    unsigned long cl, size;
    while (n--) {
        if (d_ent == 0) {
            if (!d_cl)
                d_cl = d_first;
            sd_lba = card.data_lba + (d_cl - 2) * card.spc + d_sec;
            sd_buf = secbuf;
            if (sd_read()) {
                strcpy(line, d_path[0] ? d_path : "/");
                strcat(line, ": a sector of this folder cannot be read");
                fault();
                next_dir();
                return;
            }
        }
        for (; d_ent < 16; ++d_ent) {
            e = secbuf + (d_ent << 5);
            if (!e[0]) {
                next_dir();
                return;
            }
            if (e[0] == 0xE5) {
                lfn_ok = 0;
                continue;
            }
            if (e[11] == 0x0F) {
                lfn_part(e);
                continue;
            }
            if (e[11] & 0x08 || (e[0] == '.' && (e[1] == ' ' || e[1] == '.'))) {
                lfn_ok = 0;
                continue;
            }
            name83(e, nm);
            lfn_ok = 0;
            cl = (unsigned long)le16(e + 20) << 16 | le16(e + 26);
            size = le32(e + 28);
            if (!join(path, d_path[0] ? d_path : "/", nm))
                strcpy(path, "(a long path)");
            if (e[11] & 0x10) {
                if (cl < 2 || cl > maxc) {
                    strcpy(c_path, path);
                    cfault(cl ? ": the folder's first cluster is past the end of the card: " : ": the folder has no cluster (0)", cl ? cl : 0xFFFFFFFFUL);
                } else
                    push(cl, path);
                continue;
            }
            ++n_files;
            ++d_ent;
            strcpy(c_path, path);
            if (!cl && !size)
                continue;
            chain(cl, (size + ((unsigned long)card.spc << 9) - 1) / ((unsigned long)card.spc << 9), 0);
            return;                     /* (its chain first: then on from the next entry) */
        }
        d_ent = 0;
        if (++d_sec == card.spc) {
            d_sec = 0;
            if (++d_n >= d_max) {
                next_dir();
                return;
            }
            d_cl = fat(d_cl);
        }
    }
}

/*---------------------------------------------------------------- the whole FAT */
static const unsigned char bit[8] = { 1, 2, 4, 8, 16, 32, 64, 128 };

/* (a FAT sector's 128 entries in one loop of bytes: its 16 bytes of bits
   copied out of their bank first; no long arithmetic per entry) */
static void fat_step(unsigned char n)
{
    static unsigned char bits[16];
    unsigned long c1;
    unsigned char i, last, keep, nf, nl;
    unsigned char *p;
    while (n--) {
        if (s_fat >= card.fatsz) {
            st = S_DONE;
            return;
        }
        sd_lba = card.fat_lba + s_fat;
        sd_buf = fatbuf;
        fatlba = 0xFFFFFFFFUL;
        if (sd_read()) {
            strcpy(line, "a sector of the FAT cannot be read: ");
            ui_num(line + strlen(line), s_fat);
            fault();
            st = S_DONE;
            return;
        }
        if (card.nfats > 1) {
            sd_lba += card.fatsz;
            sd_buf = secbuf;
            if (sd_read() == 0 && memcmp(fatbuf, secbuf, 512))
                ++n_fatdiff;
        }
        c1 = s_fat << 7;
        if (c1 > maxc)
            last = 0;
        else if (maxc - c1 < 127)
            last = (unsigned char)(maxc - c1) + 1;
        else
            last = 128;
        if (!nobits) {
            keep = RAMBANK;
            RAMBANK = bm + (unsigned char)(c1 >> 16);
            memcpy(bits, BANKMEM + (((unsigned int)c1 & 0xFFFF) >> 3), 16);
            RAMBANK = keep;
        }
        nf = nl = 0;
        for (i = s_fat ? 0 : 2, p = fatbuf + (i << 2); i < last; ++i, p += 4) {
            if (!(p[0] | p[1] | p[2] | (p[3] & 0x0F)))
                ++nf;
            else if (!nobits && !(bits[i >> 3] & bit[i & 7])
                     && !(p[0] == 0xF7 && p[1] == 0xFF && p[2] == 0xFF && (p[3] & 0x0F) == 0x0F))
                ++nl;
        }
        n_free += nf;
        n_lost += nl;
        ++s_fat;
    }
}

/*---------------------------------------------------------------- the job */
static void free_all(void)
{
    if (bm)
        BankFree(bm);
    if (sbank)
        BankFree(sbank);
    bm = sbank = 0;
}

static void finish(void)
{
    char *p;
    free_all();
    job = J_NONE;
    if (n_fatdiff) {
        p = ui_num(line, n_fatdiff);
        strcpy(p, " sectors of the FAT differ from its second copy");
        fault();
    }
    if (n_lost) {
        p = ui_num(line, n_lost);
        strcpy(p, " lost clusters: in use, in no file or folder (");
        p = ui_size(p + strlen(p), n_lost * card.spc << 9);
        strcpy(p, ")");
        fault();
    }
    p = ui_num(line, n_dirs);
    *p++ = ' ';
    p = ui_num(p, n_files);
    *p++ = ' ';
    p = ui_num(p, nfault);
    *p++ = ' ';
    p = ui_num(p, n_lost);
    *p++ = ' ';
    p = ui_num(p, n_free);
    *p++ = ' ';
    p = ui_num(p, n_fatdiff);
    *p++ = ' ';
    ui_num(p, card.fsi_free);
    dt_log("DT CHECK DONE ", line);
    st = S_DONE;
    if (tab == T_CHECK)
        check_draw();
    say(nfault ? "The check found problems (nothing was changed)." : "The check found no problems.");
}

void check_stop(const char *why)
{
    if (job != J_CHECK)
        return;
    free_all();
    job = J_NONE;
    st = S_IDLE;
    strcpy(line, "Stopped: ");
    strcat(line, why);
    say(line);
    dt_log("DT CHECK STOPPED ", why);
    if (tab == T_CHECK)
        check_draw();
}

void check_start(void)
{
    unsigned int need;
    if (job)
        return;
    card_read();
    if (!card.sd_ok) {
        ui_message(card.host ? "The host folder has no FAT:" : "The card cannot be checked:", card.host ? "Check needs an SD card." : card.err);
        return;
    }
    maxc = card.nclus + 1;
    need = (unsigned int)((maxc + 1) >> 16) + 1;
    nobits = 0;
    if (!fbank && !(fbank = BankAlloc(1))) {
        ui_message("Not enough memory:", "Check needs 3 RAM banks.");
        return;
    }
    if (!(sbank = BankAlloc(2))) {
        ui_message("Not enough memory:", "Check needs 3 RAM banks.");
        return;
    }
    bm = BankAlloc(need);
    nbm = need;
    if (!bm)
        nobits = 1;
    else {
        unsigned char i, keep = RAMBANK;
        for (i = 0; i < need; ++i) {
            RAMBANK = bm + i;
            memset(BANKMEM, 0, 8192);
        }
        RAMBANK = keep;
    }
    nstack = nfault = n_toomany = 0;
    n_dirs = n_files = n_lost = n_free = n_fatdiff = 0;
    fatlba = 0xFFFFFFFFUL;
    put_aside = 0;
    job = J_CHECK;
    c_path[0] = 0;
    d_first = card.root;
    chain(card.root, 0, 1);
    dt_log("DT CHECK START", "");
    if (tab == T_CHECK)
        check_draw();
}

void check_tick(void)
{
    char *p;
    static unsigned char k;
    if (put_aside) {
        check_stop("Disk Tools was put aside; the card may have changed.");
        return;
    }
    switch (st) {
    case S_CHAIN: chain_step(512); break;
    case S_DIR: dir_step(4); break;
    case S_FAT: fat_step(4); break;
    case S_DONE: finish(); return;
    }
    if (!(++k & 15)) {
        if (st == S_FAT) {
            p = ui_num(line, s_fat * 100 / card.fatsz);
            strcpy(p, "% of the FAT read (Esc stops)");
        } else {
            strcpy(line, "Folders: ");
            p = ui_num(line + 9, n_dirs);
            strcpy(p, ", files: ");
            p = ui_num(p + 9, n_files);
            strcpy(p, " (Esc stops)");
        }
        progress(line);
    }
}

