/* sysui: the card (sysui.h; DECISIONS V119).

   As the DOS lists it: the root's long listing ("$=L", DirOpen "=L": the
   lines raw, V70), whose header holds the card's name (FAT32) or the
   folder's ("HOST": the emulator's host folder, no FAT under it) and whose
   footer the free space ("n KB FREE.", MB or GB; the host's "65535 BLOCKS
   FREE." says nothing).

   As its sectors say (sd.s, read only): sector 0, an MBR (the first
   partition of type $0B or $0C, which CMDR-DOS mounts as partition 1) or
   a FAT32 boot sector itself (a card with no partition table); the boot
   sector's geometry; FSInfo's free count (the one the DOS keeps and
   lists); the CSD register's capacity (the whole card).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "sysui.h"

struct card card;
unsigned char secbuf[512];
static unsigned char de[128];

void card_dos(void)
{
    unsigned char first = 1, l;
    const char *t, *q;
    unsigned int n;
    card.host = 0;
    card.label[0] = 0;
    card.dfree = 0;
    card.dunit = 0;
    if (ChDir("/") || DirOpen("=L"))
        return;
    de[125] = 0;
    while (DirNext(de) == 0) {
        t = (const char *)de + 3;
        q = strchr(t, '"');
        if (first) {
            first = 0;
            if (strstr(t, "HOST")) {
                card.host = 1;
                strcpy(card.label, "Host folder");
            } else if (q) {
                for (++q, l = 0; *q && *q != '"' && l < 16; ++q)
                    card.label[l++] = *q;
                while (l && card.label[l - 1] == ' ')
                    --l;
                card.label[l] = 0;
            }
            continue;
        }
        if (q)
            continue;
        /* the footer: n KB, MB, GB (or the host's BLOCKS) FREE. */
        n = de[1] | de[2] << 8;
        while (*t == ' ')
            ++t;
        card.dunit = *t == 'K' || *t == 'M' || *t == 'G' ? *t : 'B';
        card.dfree = card.dunit == 'G' ? (unsigned long)n << 20 : card.dunit == 'M' ? (unsigned long)n << 10 : n;
    }
    if (curDirName[0])
        ChDir((char *)curDirName);
}

static void sd_err(const char *s)
{
    strcpy(card.err, s);
}

static unsigned char rd(unsigned long lba)
{
    sd_lba = lba;
    sd_buf = secbuf;
    return sd_read();
}

static unsigned char is_fat32(void)
{
    return secbuf[510] == 0x55 && secbuf[511] == 0xAA && le16(secbuf + 11) == 512
        && !memcmp(secbuf + 82, "FAT32", 5) && secbuf[13] && le32(secbuf + 36);
}

static void card_sd(void)
{
    unsigned char i, *e;
    unsigned long tot;
    card.sd_ok = 0;
    card.err[0] = 0;
    card.csd_kb = 0;
    card.fsi_free = 0xFFFFFFFFUL;
    if (card.host) {
        sd_err("The emulator's host folder: no FAT.");
        return;
    }
    sd_buf = secbuf;
    if (sd_csd() == 0 && (secbuf[0] >> 6) == 1)
        card.csd_kb = ((((unsigned long)(secbuf[7] & 0x3F) << 16) | (unsigned int)secbuf[8] << 8 | secbuf[9]) + 1) << 9;
    if (rd(0)) {
        sd_err("The card does not answer.");
        return;
    }
    card.ptype = 0;
    card.part_lba = 0;
    if (!is_fat32()) {
        if (secbuf[510] != 0x55 || secbuf[511] != 0xAA) {
            sd_err("Sector 0 is neither an MBR nor FAT32.");
            return;
        }
        for (i = 0, e = secbuf + 446; i < 4; ++i, e += 16)
            if (e[4] == 0x0B || e[4] == 0x0C)
                break;
        if (i == 4) {
            sd_err("The MBR has no FAT32 partition.");
            return;
        }
        card.ptype = e[4];
        card.part_lba = le32(e + 8);
        card.part_sec = le32(e + 12);
        if (rd(card.part_lba) || !is_fat32()) {
            sd_err("The partition is not FAT32.");
            return;
        }
    }
    card.spc = secbuf[13];
    card.resv = le16(secbuf + 14);
    card.nfats = secbuf[16];
    card.fatsz = le32(secbuf + 36);
    card.root = le32(secbuf + 44);
    tot = le16(secbuf + 19);
    if (!tot)
        tot = le32(secbuf + 32);
    if (!card.ptype)
        card.part_sec = tot;
    memcpy(card.vlabel, secbuf + 71, 11);
    card.vlabel[11] = 0;
    memcpy(card.fstype, secbuf + 82, 8);
    card.fstype[8] = 0;
    card.fat_lba = card.part_lba + card.resv;
    card.data_lba = card.fat_lba + card.nfats * card.fatsz;
    card.nclus = (tot - card.resv - card.nfats * card.fatsz) / card.spc;
    if (card.nclus > (card.fatsz << 7) - 2)
        card.nclus = (card.fatsz << 7) - 2;
    card.fsinfo_lba = card.part_lba + le16(secbuf + 48);
    if (rd(card.fsinfo_lba) == 0 && le32(secbuf) == 0x41615252UL && le32(secbuf + 484) == 0x61417272UL)
        card.fsi_free = le32(secbuf + 488);
    card.sd_ok = 1;
}

void card_read(void)
{
    card_dos();
    card_sd();
}
