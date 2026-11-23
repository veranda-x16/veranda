/* Calendar: a month and its days' appointments, with alarms; a Veranda
   desk accessory in C.

   The window: the month (a grid, Monday first; today on yellow, from
   Veranda's clock; the day chosen on light blue; a mark on the days with
   appointments), and the day chosen: its appointments in time order, and
   a form to add or change one (the time, the text, the alarm on or off).
   (Look 3 "Sunroom", V148: the grid's lines dotted inside a solid frame,
   the day's list with a scroll bar, the alarm a check box.)
   New fills the form (the next minute when the day is today, else
   09:00); Save keeps it; Delete takes the appointment chosen out (asked
   first); Today goes back to today; < and > change the month.

   The appointments are kept in a record file in the system folder
   ("Appointments", class "Appointments V1.0": record 0, an entry of 32
   bytes each, the year 0-99 (2000-2099), month, day, hour, minute, the
   flags (bit 0: the alarm), the text: the kernel's alarm entry's form).
   After every change the next ALARM_MAX alarms still to come go to the
   kernel (SysPrefs ALARMS_SET) and to "Veranda Alarms" in the system
   folder, which Veranda reads when it starts: a due alarm beeps and
   shows a box over any program while Veranda runs (DECISIONS V56).

   Keys: Tab between the time and the text, Return saves, the arrows move
   the day, Page Up and Down the month, Escape closes.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrwin.h>
#include <vralert.h>
#include "daui.h"

#define MAXA    120
#define TXTL    24
struct appt {
    unsigned char y, m, d, h, mi, flags;
    char text[TXTL + 2];
};
#define F_ALARM 1

#define W       576
#define GX      8               /* the grid (in the window) */
#define GY      64
#define CW      40
#define RX      304             /* the day */
#define RW      264
#define LW      248             /* (V148) the day's list (then its scroll bar, 16) */
#define RH      16
#define FILE    "Appointments"

static struct appt ap[MAXA];
static unsigned char na;
static unsigned char cy, cm, cd;        /* the day chosen (year 0-99, month, day) */
static unsigned char ty, tm, td;        /* today */
static unsigned char ch, nrows;         /* a cell's height; the day's rows */
static unsigned int fy;                 /* the form's top (in the window) */
static unsigned char dayi[MAXA], nday, sel, top;        /* the day's appointments */
static unsigned char editing;           /* the appointment in the form, $FF a new one */
static unsigned char focus;             /* 1 the time, 2 the text */
static unsigned char alarm;
static char tbuf[6], text[TXTL + 1];
static char line[64];
static struct field ftime, ftext;
static unsigned char table[ALARM_MAX * ALARM_SIZE];
static struct vrscroll bar;             /* (V148) the day's scroll bar */
extern const unsigned char vr_icon[128];        /* (alerticon.c: the Calendar's icon) */

#define NBTN 4
static const char *const btext[NBTN] = { "New", "Save", "Delete", "Today" };
static const char *const mnames[12] = { "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December" };
static const char *const dnames[7] = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
    "Saturday", "Sunday" };

#ifdef CAL_TEST
void da_test_start(void);
#endif

static char logl[64];
static void say(const char *s)
{
    *ui_put(ui_put(logl, "CAL "), s) = 0;
    LogText(logl);
}

/*---------------------------------------------------------------
  dates
 ---------------------------------------------------------------*/
static unsigned char mdays(unsigned char y, unsigned char m)
{
    static const unsigned char n[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return m == 2 && !(y & 3) ? 29 : n[m - 1];
}

/* 0 Monday .. 6 Sunday (Sakamoto's method, the years 2000-2099) */
static unsigned char wday(unsigned char y, unsigned char m, unsigned char d)
{
    static const unsigned char t[12] = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    unsigned int Y = 2000 + y - (m < 3);
    return (Y + Y / 4 - Y / 100 + Y / 400 + t[m - 1] + d + 6) % 7;
}

static long key(const struct appt *a)
{
    return ((long)a->y << 24) | ((long)a->m << 20) | ((long)a->d << 15) | (a->h << 6) | a->mi;
}

static unsigned char sameday(const struct appt *a)
{
    return a->y == cy && a->m == cm && a->d == cd;
}

/*---------------------------------------------------------------
  the file, the alarms
 ---------------------------------------------------------------*/
static void sort(void)
{
    static struct appt t;
    unsigned char i, j;
    for (i = 1; i < na; ++i) {
        t = ap[i];
        for (j = i; j && key(&ap[j - 1]) > key(&t); --j)
            ap[j] = ap[j - 1];
        ap[j] = t;
    }
}

static void load(void)
{
    na = 0;
    if (ui_rec_busy())
        return;
    sys_enter();
    if (OpenRecordFile(FILE) == 0) {
        if (usedRecords && PointRecord(0) == 0 && ReadRecord(ap, sizeof ap) == 0)
            na = (r7 - (unsigned int)ap) / sizeof(struct appt);
        CloseRecordFile();
    }
    sys_leave();
    sort();
}

/* the next alarms (after now) to the kernel and to Veranda Alarms */
static void alarms(void)
{
    struct appt now;
    unsigned char i, n = 0;
    memset(table, 0, sizeof table);
    memcpy(&now, (void *)0x054F, 5);    /* year ... minutes */
    for (i = 0; i < na && n < ALARM_MAX; ++i)
        if ((ap[i].flags & F_ALARM) && key(&ap[i]) > key(&now)) {
            memcpy(table + n * ALARM_SIZE, &ap[i], ALARM_SIZE);
            table[n * ALARM_SIZE + 5] = ALARM_ARMED;
            ++n;
        }
    SysPrefs(ALARMS_SET, table);
    sys_write("Veranda Alarms", "Veranda Alarms V1.0", "The Calendar's alarms still to come.",
              table, sizeof table);
    *ui_num(ui_put(line, "ALARMS "), n, 0) = 0;
    say(line);
}

static unsigned char save(void)
{
    unsigned char e;
    if (ui_rec_busy()) {
        ui_msg("The Calendar cannot write now.", "The program underneath has a document open.");
        return 1;
    }
    sys_enter();
    e = ui_rec_open(FILE, "Appointments V1.0", "The Calendar's appointments.");
    if (!e) {
        if (!usedRecords)
            e = AppendRecord();
        else
            e = PointRecord(0);
        if (!e)
            e = WriteRecord(ap, na * sizeof(struct appt));
        if (CloseRecordFile() && !e)
            e = DOS_ERROR;
    }
    sys_leave();
    if (e)
        ui_msg("The appointments could not be written.", "The Calendar keeps them in the system folder.");
    *ui_num(ui_put(line, "SAVED "), na, 0) = 0;
    say(line);
    alarms();
    return e;
}

/*---------------------------------------------------------------
  the month
 ---------------------------------------------------------------*/
static unsigned char first;             /* the first day's column */

static void cell_xy(unsigned char d, unsigned int *x, unsigned int *y)
{
    unsigned char k = first + d - 1;
    *x = ui_x0 + GX + (k % 7) * CW;
    *y = ui_y0 + GY + (k / 7) * ch;
}

static unsigned char busy(unsigned char d)
{
    unsigned char i;
    for (i = 0; i < na; ++i)
        if (ap[i].y == cy && ap[i].m == cm && ap[i].d == d)
            return 1;
    return 0;
}

static void draw_cell(unsigned char d)
{
    unsigned int x, y;
    unsigned char c = C_NONE;
    cell_xy(d, &x, &y);
    ui_clear(x + 1, y + 1, CW - 1, ch - 1);
    if (cy == ty && cm == tm && d == td)
        c = C_YELLOW;
    if (d == cd)
        c = C_SEL;
    ui_color(x, y, CW, ch, c);
    ui_num(line, d, 0);
    if (c != C_NONE)
        ui_bold(line, x + 4, y + 11);
    else
        ui_text(line, x + 4, y + 11);
    if (busy(d)) {
        SetPattern(1);
        WRectangle(x + CW - 10, y + ch - 8, x + CW - 6, y + ch - 4);
    }
}

static void draw_month(void)
{
    unsigned char d, n = mdays(cy, cm), i;
    unsigned int x = ui_x0 + GX, y = ui_y0 + GY;
    first = wday(cy, cm, 1);
    ui_clear(x, ui_y0 + 24, 7 * CW, 16);
    ui_color(x + 32, ui_y0 + 24, 7 * CW - 64, 16, C_NONE);
    ui_button(x, ui_y0 + 24, 24, "<", C_BTN);
    ui_button(x + 7 * CW - 24, ui_y0 + 24, 24, ">", C_BTN);
    *ui_num(ui_put(ui_put(line, mnames[cm - 1]), " "), 2000 + cy, 0) = 0;
    currentMode = SET_BOLD;
    ui_textc(line, x + 32, 7 * CW - 64, ui_y0 + 24 + 11);
    currentMode = 0;
    ui_clear(x, y, 7 * CW + 1, 6 * ch + 1);
    ui_color(x, y, 7 * CW, 6 * ch + 8, C_NONE);
    for (i = 1; i < 7; ++i)             /* (V148) dotted inside, a solid frame */
        WVerticalLine(0xAA, x + i * CW, y, y + 6 * ch);
    for (i = 1; i < 6; ++i)
        WHorizontalLine(0xAA, x, x + 7 * CW, y + i * ch);
    WFrameRectangle(0xFF, x, y, x + 7 * CW, y + 6 * ch);
    for (d = 1; d <= n; ++d)
        draw_cell(d);
}

/*---------------------------------------------------------------
  the day
 ---------------------------------------------------------------*/
static void collect(void)
{
    unsigned char i;
    nday = 0;
    for (i = 0; i < na; ++i)
        if (sameday(&ap[i]))
            dayi[nday++] = i;
}

static char *hhmm(char *p, unsigned char h, unsigned char m)
{
    p = ui_num(p, h, 2);
    *p++ = ':';
    return ui_num(p, m, 2);
}

static void draw_row(unsigned char r)
{
    unsigned int x = ui_x0 + RX, y = ui_y0 + 48 + r * RH;
    unsigned char i = top + r;
    struct appt *a;
    ui_clear(x, y, LW, RH);
    ui_color(x, y, LW, RH, i == sel && i < nday ? C_SEL : C_NONE);
    if (i >= nday) {
        if (!nday && !r)
            ui_text("No appointments.", x + 4, y + 11);
        return;
    }
    a = &ap[dayi[i]];
    hhmm(line, a->h, a->mi);
    ui_bold(line, x + 4, y + 11);
    if (a->flags & F_ALARM) {           /* a bell */
        SetPattern(1);
        WRectangle(x + 42, y + 4, x + 46, y + 10);
        WHorizontalLine(0xFF, x + 40, x + 48, y + 10);
        WRectangle(x + 43, y + 11, x + 45, y + 12);
    }
    ui_textw(a->text, x + 56, y + 11, LW - 60);
}

static void draw_day(void)
{
    unsigned char r;
    unsigned int x = ui_x0 + RX;
    collect();
    ui_clear(x, ui_y0 + 24, RW, 16);
    {
        char *p = ui_put(line, dnames[wday(cy, cm, cd)]);
        p = ui_put(ui_num(ui_put(p, " "), cd, 0), " ");
        ui_put(p, mnames[cm - 1]);
        ui_bold(line, x, ui_y0 + 24 + 11);
    }
    if (sel != 0xFF && sel >= top + nrows)
        top = sel - nrows + 1;
    if (top + nrows > nday)
        top = nday > nrows ? nday - nrows : 0;
    for (r = 0; r < nrows; ++r)
        draw_row(r);
    bar.first = top;
    bar.total = nday;
    vr_scroll(&bar);
}

static void scroll(signed char d)
{
    int t = (int)top + d;
    if (t + nrows > nday)
        t = (int)nday - nrows;
    if (t < 0)
        t = 0;
    if (t != top) {
        top = t;
        draw_day();
    }
}

static void draw_form(void)
{
    unsigned int x = ui_x0 + RX, y = ui_y0 + fy;
    ui_clear(x, y - 6, RW, 4);
    WHorizontalLine(0xFF, x, x + RW - 1, y - 6);
    ui_clear(x, y, 48, 40);
    ui_text("Time", x, y + 11);
    ui_text("What", x, y + 20 + 11);
    ui_field(&ftime, focus == 1);
    ui_field(&ftext, focus == 2);
    /* (V148) the alarm: a check box */
    ui_clear(x + 128, y, 88, UI_BH);
    ui_frame(x + 128, y + 2, 12, 12);
    if (alarm) {
        WDrawLine(DRAW_INK, x + 130, y + 8, x + 133, y + 11);
        WDrawLine(DRAW_INK, x + 133, y + 11, x + 138, y + 4);
        WDrawLine(DRAW_INK, x + 131, y + 8, x + 133, y + 10);
        WDrawLine(DRAW_INK, x + 133, y + 10, x + 137, y + 4);
    }
    ui_text("Alarm", x + 146, y + 11);
}

static unsigned int bx(unsigned char i)
{
    return ui_x0 + RX + i * 64;
}

static void draw(void)
{
    unsigned char i;
    unsigned int y;
    ui_window("Calendar", W, ui_h);
    y = ui_y0 + GY - 5;
    for (i = 0; i < 7; ++i) {           /* "Mo", "Tu" ... */
        line[0] = dnames[i][0];
        line[1] = dnames[i][1];
        line[2] = 0;
        ui_clear(ui_x0 + GX + i * CW, y - 10, CW, 12);
        ui_textc(line, ui_x0 + GX + i * CW, CW, y);
    }
    WVerticalLine(0xFF, ui_x0 + RX - 8, ui_y0 + UI_BAR + 4, ui_y0 + ui_h - 8);
    WFrameRectangle(0xFF, ui_x0 + RX - 1, ui_y0 + 47, ui_x0 + RX + LW, ui_y0 + 48 + nrows * RH);
    draw_month();
    draw_day();
    draw_form();
    for (i = 0; i < NBTN; ++i)
        ui_button(bx(i), ui_y0 + ui_h - 24, 56, btext[i], C_BTN);
}

/*---------------------------------------------------------------
  actions
 ---------------------------------------------------------------*/
static void form_from(unsigned char i)
{
    struct appt *a = &ap[i];
    hhmm(tbuf, a->h, a->mi);
    strcpy(text, a->text);
    alarm = a->flags & F_ALARM;
    editing = i;
}

static void choose(unsigned char r)
{
    if (r >= nday)
        return;
    sel = r;
    form_from(dayi[r]);
    draw_day();
    draw_form();
}

static void go_day(unsigned char y, unsigned char m, unsigned char d)
{
    unsigned char redraw = y != cy || m != cm, old = cd;
    cy = y;
    cm = m;
    cd = d;
    sel = 0xFF;
    top = 0;
    if (redraw)
        draw_month();
    else {
        draw_cell(old);
        draw_cell(d);
    }
    draw_day();
}

static void go_month(signed char dir)
{
    unsigned char y = cy, m = cm + dir, d = cd;
    if (m == 0) {
        m = 12;
        if (y)
            --y;
    } else if (m == 13) {
        m = 1;
        if (y < 99)
            ++y;
    }
    if (d > mdays(y, m))
        d = mdays(y, m);
    go_day(y, m, d);
}

static void step(signed char n)
{
    unsigned char y = cy, m = cm;
    int d = cd + n;
    if (d < 1) {
        if (--m == 0) {
            m = 12;
            --y;
        }
        d += mdays(y, m);
    } else if (d > mdays(y, m)) {
        d -= mdays(y, m);
        if (++m == 13) {
            m = 1;
            ++y;
        }
    }
    if (y > 99)
        return;
    go_day(y, m, d);
}

static void set_focus(unsigned char f)
{
    focus = f;
    draw_form();
}

static void b_new(void)
{
    unsigned char h = 9, m = 0;
    if (cy == ty && cm == tm && cd == td) {     /* today: the next minute */
        h = hour;
        m = minutes + 1;
        if (m == 60) {
            m = 0;
            if (++h == 24)
                h = 23, m = 59;
        }
    }
    hhmm(tbuf, h, m);
    text[0] = 0;
    alarm = 1;
    editing = 0xFF;
    sel = 0xFF;
    draw_day();
    set_focus(2);
}

static unsigned char parse_time(unsigned char *h, unsigned char *m)
{
    const char *p = tbuf;
    unsigned char a = 0, b = 0, n = 0;
    while (*p >= '0' && *p <= '9' && n < 2)
        a = a * 10 + *p++ - '0', ++n;
    if (!n || (*p != ':' && *p != '.' && *p))
        return 0;
    if (*p)
        ++p;
    n = 0;
    while (*p >= '0' && *p <= '9' && n < 2)
        b = b * 10 + *p++ - '0', ++n;
    if (*p || a > 23 || b > 59)
        return 0;
    *h = a;
    *m = b;
    return 1;
}

static void b_save(void)
{
    struct appt *a;
    unsigned char h, m, i;
    if (!parse_time(&h, &m)) {
        ui_msg("The time is not right.", "Type hours and minutes, for example 14:30.");
        return;
    }
    if (editing == 0xFF) {
        if (na >= MAXA) {
            ui_msg("The Calendar is full.", "It keeps 120 appointments at most.");
            return;
        }
        editing = na++;
    }
    a = &ap[editing];
    a->y = cy;
    a->m = cm;
    a->d = cd;
    a->h = h;
    a->mi = m;
    a->flags = alarm ? F_ALARM : 0;
    memset(a->text, 0, sizeof a->text);
    strncpy(a->text, text, TXTL);
    sort();
    save();
    collect();
    sel = 0xFF;
    for (i = 0; i < nday; ++i)          /* the one saved, chosen */
        if (ap[dayi[i]].h == h && ap[dayi[i]].mi == m && !strcmp(ap[dayi[i]].text, a->text))
            sel = i;
    if (sel != 0xFF)
        editing = dayi[sel];
    draw_cell(cd);
    draw_day();
    draw_form();
}

static void b_delete(void)
{
    unsigned char i;
    if (sel >= nday)
        return;
    if (!ui_ask("Delete this appointment?", ap[dayi[sel]].text))
        return;
    i = dayi[sel];
    memmove(&ap[i], &ap[i + 1], (na - i - 1) * sizeof(struct appt));
    --na;
    save();
    say("DELETED");
    sel = 0xFF;
    editing = 0xFF;
    draw_cell(cd);
    draw_day();
}

static void close_box(void)
{
    say("CLOSED");
    RstrAppl();
}

static void act(unsigned char b)
{
    switch (b) {
    case 0: b_new(); break;
    case 1: b_save(); break;
    case 2: b_delete(); break;
    case 3: go_day(ty, tm, td); break;
    }
}

/* otherPressVec */
static void press(void)
{
    unsigned char i, k;
    unsigned int x = ui_x0 + GX, y = ui_y0 + GY;
    if (!ui_press())
        return;
    if (ui_closebox()) {
        close_box();
        return;
    }
    if (ui_in(x, ui_y0 + 24, 24, UI_BH)) {
        go_month(-1);
        return;
    }
    if (ui_in(x + 7 * CW - 24, ui_y0 + 24, 24, UI_BH)) {
        go_month(1);
        return;
    }
    if (ui_in(x, y, 7 * CW, 6 * ch)) {
        k = (ui_py - y) / ch * 7 + (ui_px - x) / CW;
        if (k >= first && k - first < mdays(cy, cm))
            go_day(cy, cm, k - first + 1);
        return;
    }
    switch (vr_scroll_hit(&bar, ui_px, ui_py)) {   /* (V148) the scroll bar */
    case VS_BACK: scroll(-1); return;
    case VS_FWD: scroll(1); return;
    case VS_PGBACK: scroll(-(signed char)nrows); return;
    case VS_PGFWD: scroll(nrows); return;
    case VS_THUMB: return;
    }
    if (ui_in(ui_x0 + RX, ui_y0 + 48, LW, nrows * RH)) {
        choose(top + (ui_py - ui_y0 - 48) / RH);
        return;
    }
    if (ui_in(ftime.x, ftime.y, ftime.w, UI_BH)) {
        set_focus(1);
        return;
    }
    if (ui_in(ftext.x, ftext.y, ftext.w, UI_BH)) {
        set_focus(2);
        return;
    }
    if (ui_in(ui_x0 + RX + 128, ui_y0 + fy, 88, UI_BH)) {
        alarm ^= 1;
        draw_form();
        return;
    }
    for (i = 0; i < NBTN; ++i)
        if (ui_in(bx(i), ui_y0 + ui_h - 24, 56, UI_BH)) {
            act(i);
            return;
        }
}

static void typed(void)
{
    unsigned char c = keyData;
    if (c == 27) {
        close_box();
        return;
    }
    if (keyDataMods & KEYM_ARROW) {
        if (c == KEY_LEFT)
            step(-1);
        else if (c == KEY_RIGHT)
            step(1);
        else if (c == KEY_UP)
            step(-7);
        else if (c == KEY_DOWN)
            step(7);
        return;
    }
    if (c == KEY_PGUP) {
        go_month(-1);
        return;
    }
    if (c == KEY_PGDN) {
        go_month(1);
        return;
    }
    if (c == KEY_TAB) {
        set_focus(focus == 1 ? 2 : 1);
        return;
    }
    if (c == 13) {
        b_save();
        return;
    }
    if (focus && ui_field_key(focus == 1 ? &ftime : &ftext, c))
        draw_form();
}

static void track(void)
{
    ui_px = mouseXPos;
    ui_py = mouseYPosW;
    SetPointer(ui_in(ftime.x, ftime.y, ftime.w, UI_BH) || ui_in(ftext.x, ftext.y, ftext.w, UI_BH)
               ? PTR_IBEAM : PTR_ARROW);
}

int main(void)
{
    vr_alert_icon = vr_icon;
    if (screenWidth < 640) {
        ui_msg("The Calendar needs a screen 640 wide.", "");
        RstrAppl();
    }
#ifdef CAL_TEST
    SetClock(126, 11, 16, 11, 59, 30, 2);       /* (gate da: 2026-11-16 11:59:30) */
#endif
    ui_h = screenHeight >= 400 ? 400 : 232;
    ch = ui_h >= 400 ? 48 : 24;
    fy = ui_h - 8 - 24 - 44;
    nrows = (fy - 8 - 48) / RH;
    ui_x0 = ((screenWidth - W) / 2) & ~7;
    ui_y0 = ((screenHeight - ui_h) / 2) & ~7;
    bar.cx = (ui_x0 + RX + LW) >> 3;
    bar.cy = (ui_y0 + 48) >> 3;
    bar.len = nrows << 1;
    bar.vert = 1;
    bar.shown = nrows;
    ftime.x = ui_x0 + RX + 40;
    ftime.y = ui_y0 + fy;
    ftime.w = 64;
    ftime.buf = tbuf;
    ftime.max = 5;
    ftext.x = ui_x0 + RX + 40;
    ftext.y = ui_y0 + fy + 20;
    ftext.w = RW - 40;
    ftext.buf = text;
    ftext.max = TXTL;
    ty = cy = year;
    tm = cm = month;
    td = cd = day;
    if (!tm || tm > 12)
        tm = cm = 1;
    if (!td || td > 31)
        td = cd = 1;
    load();
    sel = 0xFF;
    editing = 0xFF;
    strcpy(tbuf, "09:00");
    alarm = 1;
    draw();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(typed);
    appMain = VR_FN(track);
    *ui_num(ui_put(line, "RUNNING "), na, 0) = 0;
    say(line);
#ifdef CAL_TEST
    da_test_start();
#endif
    return 0;
}
