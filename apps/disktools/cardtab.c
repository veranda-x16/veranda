/* Disk Tools: the Card tab (DECISIONS V119): the card's name (Rename...:
   CMDR-DOS's "R-H:name", which renames the FAT32 volume, on the kernel's
   command channel: sysui's dos.s), its file system and partition, size,
   free space, cluster size, FATs and boot sector, as sysui's card.c read
   them. Its code is overlay 2 (main.c's wrappers map it). MIT licence
   (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "dt.h"
#pragma code-name ("OVERLAY2")

#define CY (BODY_TOP + 8)

static char *pair_size(char *p, unsigned long sectors)
{
    p = ui_size(p, sectors << 9);
    strcpy(p, " (");
    p = ui_num(p + 2, sectors);
    strcpy(p, " sectors)");
    return p + strlen(p);
}

void card_draw_o(void)
{
    unsigned int y = CY, x;
    char *p;
    ui_clear(BODY_TOP, BODY_BOT);
    x = 16 + ui_text(16, y, "The SD card", 1) + 24;
    if (!card.host)
        ui_button(x, y + 1, "Rename...", H_RENAME);
    y += 24;
    ui_pair(y, "Name", card.label[0] ? card.label : "(none)");
    y += LINE_H;
    if (card.host) {
        ui_pair(y, "File system", "the emulator's host folder: no FAT, no sectors");
        y += LINE_H * 2;
        ui_text(16, y, "Space use and Clean up work here; Check needs an SD card (or its image).", 0);
        return;
    }
    if (!card.sd_ok) {
        ui_pair(y, "File system", card.err);
        return;
    }
    p = line;
    if (card.ptype) {
        strcpy(p, "FAT32 in the MBR's partition (type ");
        p = ui_hex(p + strlen(p), card.ptype, 2);
        strcpy(p, ") from sector ");
        ui_num(p + 14, card.part_lba);
    } else
        strcpy(p, "FAT32, no partition table");
    ui_pair(y, "File system", line);
    y += LINE_H;
    p = pair_size(line, card.part_sec);
    if (card.csd_kb) {
        strcpy(p, "; the card ");
        ui_size(p + 11, card.csd_kb << 10);
    }
    ui_pair(y, "Size", line);
    y += LINE_H;
    p = line;
    if (card.fsi_free != 0xFFFFFFFFUL) {
        p = ui_size(p, card.fsi_free * card.spc << 9);
        strcpy(p, " (");
        p = ui_num(p + 2, card.fsi_free);
        strcpy(p, " clusters, FSInfo's count)");
        p += strlen(p);
    }
    if (card.dunit && card.dunit != 'B') {
        strcpy(p, p == line ? "" : "; ");
        p += strlen(p);
        strcpy(p, "the DOS lists ");
        p = ui_size(p + 14, card.dfree << 10);
    }
    ui_pair(y, "Free", line);
    y += LINE_H;
    p = ui_size(line, (unsigned long)card.spc << 9);
    strcpy(p, " (");
    p = ui_num(p + 2, card.spc);
    strcpy(p, card.spc == 1 ? " sector); " : " sectors); ");
    p = ui_num(p + strlen(p), card.nclus);
    strcpy(p, " clusters");
    ui_pair(y, "Cluster size", line);
    y += LINE_H;
    p = ui_num(line, card.nfats);
    strcpy(p, card.nfats == 1 ? " copy of " : " copies of ");
    p = ui_num(p + strlen(p), card.fatsz);
    strcpy(p, " sectors; ");
    p = ui_num(p + 10, card.resv);
    strcpy(p, " reserved sectors; the root at cluster ");
    ui_num(p + strlen(p), card.root);
    ui_pair(y, "FAT", line);
    y += LINE_H;
    strcpy(line, "\"");
    strcat(line, card.vlabel);
    strcat(line, "\" (the boot sector's copy of the name), \"");
    strcat(line, card.fstype);
    strcat(line, "\"");
    ui_pair(y, "Boot sector", line);
    y += LINE_H * 2;
    ui_text(16, y, "No formatting here: Veranda runs from this card.", 0);
}

void card_log_o(void)
{
#ifdef DT_TEST
    char *p = line;
    p = ui_num(p, card.host);
    *p++ = ' ';
    p = ui_num(p, card.sd_ok);
    *p++ = ' ';
    p = ui_num(p, card.part_sec);
    *p++ = ' ';
    p = ui_num(p, card.spc);
    *p++ = ' ';
    p = ui_num(p, card.nclus);
    *p++ = ' ';
    p = ui_num(p, card.fsi_free);
    *p++ = ' ';
    p = ui_num(p, card.dfree);
    *p++ = ' ';
    p = ui_num(p, card.csd_kb);
    *p++ = ' ';
    strcpy(p, card.label);
    dt_log("DT CARD ", line);
#endif
}

void card_rename_o(void)
{
    static char nm[16], reply[44];
    unsigned char i, c;
    if (job || card.host)
        return;
    strcpy(nm, card.label);
    if (!ui_ask("The card's new name (11 at most):", nm, 11) || !nm[0])
        return;
    for (i = 0; (c = nm[i]) != 0; ++i) {
        if (c >= 'a' && c <= 'z')
            nm[i] = c - 32;
        else if (c < 32 || c > 126 || strchr("*?.,;:/\\|+=<>[]\"", c)) {
            ui_message("A card's name cannot hold", "* ? . , ; : / \\ | + = < > [ ] \"");
            return;
        }
    }
    ChDir("/");                         /* (the kernel's command channel open) */
    strcpy(line, "R-H:");
    strcat(line, nm);
    if (dos_send(line))
        strcpy(reply, "no command channel");
    else
        dos_reply(reply, 40);
    dt_log("DT RENAME ", reply);
    if (reply[0] != '0' || reply[1] > '1') {
        ui_message("Not renamed. The DOS said:", reply);
        return;
    }
    card_read();
    card_log_o();
    card_draw_o();
    say("The card was renamed.");
}

