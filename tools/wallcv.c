/* wallcv: a 640 x 480 RGB picture -> VERA 4 bpp 8 x 8 tiles, their map
   and palette rows: Veranda's tile desktop picture (DECISIONS V101; built
   and run by tools/mkwall.py, from the feasibility trial's tilecv).

   wallcv in.rgb outprefix firstrow rows maxtiles dither [firstcard [colours]]
     in.rgb     640 x 480 x 3 bytes; or several such screens one after
                the other (up to 4: a program's picture and its other
                states, mkwall.py --tiles, DECISIONS V105), converted
                together: the same tiles and palette rows, a map each
     firstrow   the first palette row the picture may use (2), rows how
                many (11: rows 2-12, version 3, V102; 12: rows 2-13, version 2; row 0 is the UI's, 1 the sprites',
                14 the highlight row, 15 the covered row)
     maxtiles   the tiles in all, the 16 solid ones (tile c: every pixel
                c) first (480: $13000-$16BFF)
     dither     1: a 4 x 4 Bayer dither of +-12 added to the targets
                (gradients); 0: none (a picture in few colours comes out
                exact when it fits)
     firstcard  the first card row converted (2: rows 0-1 are under the
                menu bar); the rows above it get tile 0 (paper)
     colours    the indices a row's pixels use: 1 .. colours (15; 10 for a
                wallpaper of version 3, whose rows keep 11-15 for the
                shell's chrome: DECISIONS V102)
   Writes outprefix.tiles (n * 32 bytes, VERA's 4 bpp: high nibble the
   left pixel), .map (80 x 60 entries a screen of 2 bytes: the tile's low byte;
   palette row << 4 | vflip << 3 | hflip << 2 | the tile's bits 8-9),
   .pal (rows * 16 words, $0RGB little-endian; index 0 of a row unused);
   prints "RESULT ..." on stdout. Tile pixel 0 is transparent (layer 0
   shows palette entry 0 there), so the picture uses indices 1-15.
   MIT licence (see LICENSE). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
static int NC1 = 16;              /* 1 + the colours a row may use (indices 1 .. NC1 - 1) */

#define W 640
#define H 480
#define SCRMAX 4
#define CW 80
#define CH 60
#define CHMAX (CH * SCRMAX)

static unsigned char img[H * SCRMAX][W][3];
static int nscr = 1;               /* screens */
static float pal[16][16][3];      /* row, index, rgb (0-255) */
static int palw[16][16];          /* 12-bit */
static int rowok[16];
static int ncell, cell0;
static float tgt[CW * CHMAX][64][3];
static int crow[CW * CHMAX];
static const float WT[3] = { 0.30f, 0.59f, 0.11f };
static int dither;
static const int BAYER[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };

static float d2(const float *a, const float *b)
{
    float r = a[0] - b[0], g = a[1] - b[1], bb = a[2] - b[2];
    return WT[0] * r * r + WT[1] * g * g + WT[2] * bb * bb;
}

static int snap(float v) { int q = (int)lrintf(v / 17.0f); return q < 0 ? 0 : q > 15 ? 15 : q; }

static void setcol(int r, int i, float *c)
{
    int q0 = snap(c[0]), q1 = snap(c[1]), q2 = snap(c[2]);
    palw[r][i] = q0 << 8 | q1 << 4 | q2;
    pal[r][i][0] = q0 * 17; pal[r][i][1] = q1 * 17; pal[r][i][2] = q2 * 17;
}

/* a cell's pixel's target, dithered if asked */
static void target(int c, int p, float *o)
{
    for (int k = 0; k < 3; ++k) o[k] = tgt[c][p][k];
    if (dither) {
        int x = p & 7, y = p >> 3;
        float d = (BAYER[(y & 3) * 4 + (x & 3)] - 7.5f) * 1.6f;  /* +-12 of 255 */
        for (int k = 0; k < 3; ++k) o[k] += d;
    }
}

static float cell_err_row(int c, int r)
{
    float e = 0, t[3];
    for (int p = 0; p < 64; ++p) {
        float b = 1e30f;
        target(c, p, t);
        for (int i = 1; i < NC1; ++i) { float d = d2(t, pal[r][i]); if (d < b) b = d; }
        e += b;
    }
    return e;
}

/* tiles */
typedef struct { unsigned char px[64]; } Tile;
static Tile ct[CW * CHMAX];          /* each cell's quantized pattern */
static float E[CW * CHMAX][64][16];  /* error of index i at pixel p of cell c (real target, no dither) */

static void orient(const unsigned char *s, unsigned char *d, int o)
{
    for (int y = 0; y < 8; ++y)
        for (int x = 0; x < 8; ++x) {
            int sx = o & 1 ? 7 - x : x, sy = o & 2 ? 7 - y : y;
            d[y * 8 + x] = s[sy * 8 + sx];
        }
}

static Tile *pat; static int npat;

/* cell c's card: x, and its row counted over all the screens */
static void cellxy(int c, int firstrow, int *cx, int *cy)
{
    int per = (CH - firstrow) * CW, s = c / per, k = c % per;
    *cx = k % CW;
    *cy = s * CH + k / CW + firstrow;
}
static int *asg, *aor;            /* cell -> pattern, orientation */

int main(int argc, char **argv)
{
    if (argc < 7) {
        fprintf(stderr, "usage: wallcv in.rgb outprefix firstrow rows maxtiles dither [firstcard [colours]]\n");
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    size_t got = fread(img, 1, sizeof img, f);
    fclose(f);
    nscr = (int)(got / (W * H * 3));
    if (nscr < 1 || got != (size_t)nscr * W * H * 3) {
        fprintf(stderr, "wallcv: %s: not 1-%d screens of 640 x 480\n", argv[1], SCRMAX);
        return 1;
    }
    const char *out = argv[2];
    int prow = atoi(argv[3]), nrows = atoi(argv[4]), maxt = atoi(argv[5]);
    dither = atoi(argv[6]);
    int firstrow = argc > 7 ? atoi(argv[7]) : 2;
    NC1 = (argc > 8 ? atoi(argv[8]) : 15) + 1;
    if (prow < 1 || nrows < 1 || prow + nrows > 16 || maxt < 17 || maxt > 1024 || firstrow < 0 || firstrow >= CH
        || NC1 < 3 || NC1 > 16) {
        fprintf(stderr, "wallcv: bad arguments\n");
        return 1;
    }
    cell0 = firstrow * CW;
    ncell = nscr * (CH - firstrow) * CW;
    for (int c = 0; c < ncell; ++c) {
        int cx, cy;
        cellxy(c, firstrow, &cx, &cy);
        for (int p = 0; p < 64; ++p)
            for (int k = 0; k < 3; ++k) tgt[c][p][k] = img[cy * 8 + (p >> 3)][cx * 8 + (p & 7)][k];
    }
    int frow[16], nf = 0;
    for (int r = prow; r < prow + nrows; ++r) frow[nf++] = r, rowok[r] = 1;
    /* rows: k-means of cells by mean colour for a start */
    static float mean[CW * CHMAX][3];
    for (int c = 0; c < ncell; ++c) {
        mean[c][0] = mean[c][1] = mean[c][2] = 0;
        for (int p = 0; p < 64; ++p) for (int k = 0; k < 3; ++k) mean[c][k] += tgt[c][p][k] / 64;
    }
    float cen[16][3];
    for (int j = 0; j < nf; ++j) memcpy(cen[j], mean[(long)ncell * (2 * j + 1) / (2 * nf)], sizeof cen[j]);
    /* farthest-point start */
    memcpy(cen[0], mean[ncell / 2], sizeof cen[0]);
    for (int j = 1; j < nf; ++j) {
        float far = -1; int fi = 0;
        for (int c = 0; c < ncell; ++c) {
            float b = 1e30f;
            for (int k = 0; k < j; ++k) { float d = d2(mean[c], cen[k]); if (d < b) b = d; }
            if (b > far) far = b, fi = c;
        }
        memcpy(cen[j], mean[fi], sizeof cen[j]);
    }
    for (int it = 0; it < 15; ++it) {
        float acc[16][4] = { { 0 } };
        for (int c = 0; c < ncell; ++c) {
            int bj = 0; float b = 1e30f;
            for (int j = 0; j < nf; ++j) { float d = d2(mean[c], cen[j]); if (d < b) b = d, bj = j; }
            crow[c] = frow[bj];
            for (int k = 0; k < 3; ++k) acc[bj][k] += mean[c][k];
            acc[bj][3] += 1;
        }
        for (int j = 0; j < nf; ++j) if (acc[j][3]) for (int k = 0; k < 3; ++k) cen[j][k] = acc[j][k] / acc[j][3];
    }
    /* alternate: per row 15 colours by k-means over its cells' pixels; cells to the best row */
    for (int it = 0; it < 8; ++it) {
        for (int j = 0; j < nf; ++j) {
            int r = frow[j];
            /* gather pixels */
            static float pts[CW * CHMAX * 64][3]; int np = 0;
            for (int c = 0; c < ncell; ++c) if (crow[c] == r)
                for (int p = 0; p < 64; ++p) target(c, p, pts[np++]);
            if (!np) continue;
            float cc[16][3];
            /* start: previous palette, or spread */
            if (it == 0) {
                memcpy(cc[1], pts[0], sizeof cc[1]);
                for (int i = 2; i < NC1; ++i) {
                    float far = -1; int fi = 0;
                    for (int q = 0; q < np; q += 13) {
                        float b = 1e30f;
                        for (int k = 1; k < i; ++k) { float d = d2(pts[q], cc[k]); if (d < b) b = d; }
                        if (b > far) far = b, fi = q;
                    }
                    memcpy(cc[i], pts[fi], sizeof cc[i]);
                }
            } else memcpy(cc, pal[r], sizeof cc);
            for (int k2 = 0; k2 < 10; ++k2) {
                double acc[16][4] = { { 0 } };
                for (int q = 0; q < np; ++q) {
                    int bi = 1; float b = 1e30f;
                    for (int i = 1; i < NC1; ++i) { float d = d2(pts[q], cc[i]); if (d < b) b = d, bi = i; }
                    for (int k = 0; k < 3; ++k) acc[bi][k] += pts[q][k];
                    acc[bi][3] += 1;
                }
                for (int i = 1; i < NC1; ++i) if (acc[i][3]) for (int k = 0; k < 3; ++k) cc[i][k] = acc[i][k] / acc[i][3];
            }
            pal[r][0][0] = pal[r][0][1] = pal[r][0][2] = 255;
            for (int i = 1; i < NC1; ++i) setcol(r, i, cc[i]);
        }
        double tot = 0; int moved = 0;
        for (int c = 0; c < ncell; ++c) {
            int br = crow[c]; float b = cell_err_row(c, br);
            for (int r = 0; r < 16; ++r) if (rowok[r] && r != crow[c]) {
                float e = cell_err_row(c, r);
                if (e < b) b = e, br = r;
            }
            if (br != crow[c]) moved++, crow[c] = br;
            tot += b;
        }
        if (getenv("WALLCV_LOG")) fprintf(stderr, "row fit %d: err/px %.1f, moved %d\n", it, tot / ncell / 64, moved);
    }
    /* quantize: patterns; E tables */
    for (int c = 0; c < ncell; ++c) {
        int r = crow[c];
        for (int p = 0; p < 64; ++p) {
            float t[3]; target(c, p, t);
            int bi = 1; float b = 1e30f;
            for (int i = 1; i < NC1; ++i) { float d = d2(t, pal[r][i]); if (d < b) b = d, bi = i; }
            ct[c].px[p] = bi;
            E[c][p][0] = 1e9f;
            for (int i = 1; i < NC1; ++i) E[c][p][i] = d2(t, pal[r][i]);
            for (int i = NC1; i < 16; ++i) E[c][p][i] = 1e9f;
        }
    }
    /* unique patterns, with flips */
    pat = malloc(sizeof(Tile) * (ncell + 16));
    asg = malloc(sizeof(int) * ncell); aor = malloc(sizeof(int) * ncell);
    npat = 0;
    for (int i = 0; i < 16; ++i) memset(pat[npat++].px, i, 64);   /* the solid tiles */
    int noflip_unique = 0;
    {
        /* count without flips */
        Tile *tmp = malloc(sizeof(Tile) * ncell); int n = 0;
        for (int c = 0; c < ncell; ++c) {
            int k; for (k = 0; k < n; ++k) if (!memcmp(tmp[k].px, ct[c].px, 64)) break;
            if (k == n) tmp[n++] = ct[c];
        }
        noflip_unique = n; free(tmp);
    }
    for (int c = 0; c < ncell; ++c) {
        int found = -1, fo = 0;
        for (int o = 0; o < 4 && found < 0; ++o) {
            unsigned char t[64]; orient(ct[c].px, t, o);
            for (int k = 0; k < npat; ++k) if (!memcmp(pat[k].px, t, 64)) { found = k; fo = o; break; }
        }
        if (found < 0) { pat[npat] = ct[c]; found = npat++; fo = 0; }
        asg[c] = found; aor[c] = fo;
    }
    int uniq = npat;
    int solidused = 0;
    for (int c = 0; c < ncell; ++c) if (asg[c] < 16) solidused++;
    if (getenv("WALLCV_LOG"))
        fprintf(stderr, "unique tiles: %d without flips, %d with flips + 16 solid; cells on solid tiles %d\n",
                noflip_unique, uniq, solidused);
    /* reduce to maxt: lazy greedy removal over each cell's best-K candidates */
    if (npat > maxt) {
        enum { K = 64 };
        typedef struct { int p, o; float e; } Cand;
        Cand *cand = malloc(sizeof(Cand) * K * ncell);
        int *cn = calloc(ncell, sizeof(int));
        #pragma omp parallel for schedule(dynamic, 16)
        for (int c = 0; c < ncell; ++c) {
            Cand best[K]; int nb = 0;
            for (int p = 0; p < npat; ++p)
                for (int o = 0; o < 4; ++o) {
                    unsigned char t[64]; orient(pat[p].px, t, o);
                    /* early-out partial sum */
                    float lim = nb == K ? best[K - 1].e : 1e30f, e = 0;
                    int i;
                    for (i = 0; i < 64 && e < lim; ++i) e += E[c][i][t[i]];
                    if (e >= lim) continue;
                    int j = nb < K ? nb++ : K - 1;
                    while (j > 0 && best[j - 1].e > e) { best[j] = best[j - 1]; --j; }
                    best[j].p = p; best[j].o = o; best[j].e = e;
                    if (p < 16) break;   /* solids: orientation irrelevant */
                }
            /* keep only the best orientation per pattern */
            int m = 0;
            for (int a = 0; a < nb; ++a) {
                int dup = 0;
                for (int b = 0; b < m; ++b) if (cand[(long)c * K + b].p == best[a].p) dup = 1;
                if (!dup) cand[(long)c * K + m++] = best[a];
            }
            cn[c] = m;
        }
        char *alive = malloc(npat); memset(alive, 1, npat);
        int *cur = malloc(sizeof(int) * ncell);     /* index into cand of the current choice */
        for (int c = 0; c < ncell; ++c) cur[c] = 0;
        /* cells by pattern: rebuilt on demand by scanning (ncell small) */
        int live = npat;
        float *cost = malloc(sizeof(float) * npat);
        #define NEXTE(c) ({ int _k = cur[c] + 1; while (_k < cn[c] && !alive[cand[(long)(c) * K + _k].p]) ++_k; \
                           _k < cn[c] ? cand[(long)(c) * K + _k].e : 1e7f; })
        /* lists of cells per pattern */
        int *head = malloc(sizeof(int) * npat), *nxt = malloc(sizeof(int) * ncell);
        while (live > maxt) {
            /* recompute all costs (simple; npat * few) */
            for (int p = 0; p < npat; ++p) head[p] = -1, cost[p] = 0;
            for (int c = 0; c < ncell; ++c) {
                int p = cand[(long)c * K + cur[c]].p;
                nxt[c] = head[p]; head[p] = c;
            }
            for (int p = 0; p < npat; ++p) {
                if (!alive[p]) continue;
                float s = 0;
                for (int c = head[p]; c >= 0; c = nxt[c]) s += NEXTE(c) - cand[(long)c * K + cur[c]].e;
                cost[p] = s;
            }
            /* remove a batch of the cheapest (1% of what is left, at least 1) */
            int batch = (live - maxt) / 20 + 1;
            for (int b = 0; b < batch && live > maxt; ++b) {
                int bp = -1; float bc = 1e30f;
                for (int p = 16; p < npat; ++p) if (alive[p] && cost[p] < bc) bc = cost[p], bp = p;
                alive[bp] = 0; live--;
                for (int c = head[bp]; c >= 0; c = nxt[c]) {
                    int k = cur[c] + 1;
                    while (k < cn[c] && !alive[cand[(long)c * K + k].p]) ++k;
                    if (k >= cn[c]) { /* fall back to the best solid */
                        k = 0; while (cand[(long)c * K + k].p >= 16 && k < cn[c] - 1) ++k;
                    }
                    cur[c] = k;
                }
                /* invalidate costs of patterns touched: they get recomputed next round;
                   mark the removed one's cells' new patterns as expensive for this batch */
                for (int c = head[bp]; c >= 0; c = nxt[c]) cost[cand[(long)c * K + cur[c]].p] = 1e30f;
                head[bp] = -1;
            }
        }
        for (int c = 0; c < ncell; ++c) { asg[c] = cand[(long)c * K + cur[c]].p; aor[c] = cand[(long)c * K + cur[c]].o; }
        /* compact */
        int *re = malloc(sizeof(int) * npat), n = 0;
        for (int p = 0; p < npat; ++p) if (alive[p]) { re[p] = n; pat[n++] = pat[p]; } else re[p] = -1;
        for (int c = 0; c < ncell; ++c) asg[c] = re[asg[c]];
        npat = n;
        /* k-means refinement: per pixel best index for each pattern's cells, then reassign */
        for (int it = 0; it < 4; ++it) {
            for (int p = 16; p < npat; ++p) {
                float acc[64][16]; memset(acc, 0, sizeof acc); int any = 0;
                for (int c = 0; c < ncell; ++c) if (asg[c] == p) {
                    any = 1;
                    for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) {
                        int sx = aor[c] & 1 ? 7 - x : x, sy = aor[c] & 2 ? 7 - y : y;
                        for (int i = 1; i < NC1; ++i) acc[sy * 8 + sx][i] += E[c][y * 8 + x][i];
                    }
                }
                if (!any) continue;
                for (int q = 0; q < 64; ++q) { int bi = 1; for (int i = 2; i < NC1; ++i) if (acc[q][i] < acc[q][bi]) bi = i; pat[p].px[q] = bi; }
            }
            double tot = 0;
            #pragma omp parallel for reduction(+:tot) schedule(dynamic, 16)
            for (int c = 0; c < ncell; ++c) {
                float b = 1e30f; int bp = 0, bo = 0;
                for (int p = 0; p < npat; ++p) for (int o = 0; o < (p < 16 ? 1 : 4); ++o) {
                    unsigned char t[64]; orient(pat[p].px, t, o);
                    float e = 0; int i;
                    for (i = 0; i < 64 && e < b; ++i) e += E[c][i][t[i]];
                    if (e < b) b = e, bp = p, bo = o;
                }
                asg[c] = bp; aor[c] = bo; tot += b;
            }
            if (getenv("WALLCV_LOG")) fprintf(stderr, "refine %d: err/px %.1f\n", it, tot / ncell / 64);
        }
    }
    /* outputs */
    char fn[512];
    int used = 0; { char *u = calloc(npat, 1); for (int c = 0; c < ncell; ++c) u[asg[c]] = 1; for (int p = 0; p < npat; ++p) used += u[p]; free(u); }
    sprintf(fn, "%s.tiles", out); f = fopen(fn, "wb");
    if (!f) { perror(fn); return 1; }
    for (int p = 0; p < npat; ++p) for (int q = 0; q < 64; q += 2) fputc(pat[p].px[q] << 4 | pat[p].px[q + 1], f);
    fclose(f);
    static unsigned char map[CHMAX][CW][2];
    for (int c = 0; c < ncell; ++c) {
        int cx, cy, t = asg[c], o = aor[c];
        cellxy(c, firstrow, &cx, &cy);
        map[cy][cx][0] = t & 255;
        map[cy][cx][1] = crow[c] << 4 | (o & 2 ? 8 : 0) | (o & 1 ? 4 : 0) | t >> 8;
    }
    sprintf(fn, "%s.map", out); f = fopen(fn, "wb");
    if (!f) { perror(fn); return 1; }
    fwrite(map, 1, (size_t)nscr * CH * CW * 2, f); fclose(f);
    sprintf(fn, "%s.pal", out); f = fopen(fn, "wb");
    if (!f) { perror(fn); return 1; }
    for (int r = prow; r < prow + nrows; ++r) for (int i = 0; i < 16; ++i) {
        int w = i ? palw[r][i] : 0;
        fputc(w & 0xFF, f); fputc(w >> 8, f);
    }
    fclose(f);
    /* the error against the picture */
    double se = 0, sen = 0;
    for (int c = 0; c < ncell; ++c) {
        int cx, cy, t = asg[c], r = crow[c], fl = aor[c];
        cellxy(c, firstrow, &cx, &cy);
        for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) {
            int sx = fl & 1 ? 7 - x : x, sy = fl & 2 ? 7 - y : y;
            int v = pat[t].px[sy * 8 + sx];
            for (int k = 0; k < 3; ++k) {
                float d = (v ? pal[r][v][k] : 255) - (float)img[cy * 8 + y][cx * 8 + x][k];
                se += d * d; sen++;
            }
        }
    }
    int rows_used = 0; { int ru[16] = { 0 }; for (int c = 0; c < ncell; ++c) ru[crow[c]] = 1; for (int r = 0; r < 16; ++r) rows_used += ru[r]; }
    if (se == 0)
        printf("RESULT unique=%d tiles=%d used=%d rows=%d exact\n", uniq, npat, used, rows_used);
    else
        printf("RESULT unique=%d tiles=%d used=%d rows=%d psnr=%.2f\n", uniq, npat, used, rows_used,
               10 * log10(255.0 * 255.0 / (se / sen)));
    return 0;
}
