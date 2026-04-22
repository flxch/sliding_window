/**
 * test_sliding_window.c  –  unit tests for sliding_window.{h,c}
 *
 * Build:
 *   gcc -std=c99 -Wall -Wextra -g -fsanitize=address \
 *       sliding_window.c test_sliding_window.c -o test_sw_c
 *
 * Run:
 *   ./test_sw_c
 */

#include "sliding_window.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ────────────────────────────────────────────────────────────────────
 * Tiny test framework
 * ──────────────────────────────────────────────────────────────────── */
static int g_passed = 0, g_failed = 0;

#define CHECK(cond, msg)                                              \
    do {                                                              \
        if (cond) { printf("  PASS  %s\n", msg); g_passed++;         \
        } else    { printf("  FAIL  %s  (line %d)\n", msg, __LINE__);\
                    g_failed++; }                                     \
    } while (0)

/* ────────────────────────────────────────────────────────────────────
 * Combined test context
 * Shared by both the next_fn and the emit_fn via the single user_data
 * pointer provided by the API.
 * ──────────────────────────────────────────────────────────────────── */
typedef struct {
    /* input stream */
    const int *xs;
    int        nx;
    int        pos;
    /* result collector */
    int       *results;
    int        res_cap;
    int        res_len;
    /* operator selector */
    int        op_kind;  /* 0=add, 1=max, 2=min */
} Ctx;

/* ── callbacks ───────────────────────────────────────────────────────── */

/* Pack an int into void* by value (safe for the range of ints we test). */
static void *pack(int v)   { return (void *)(intptr_t)v; }
static int   unpack(void *p) { return (int)(intptr_t)p; }

static int ctx_next(void *ud, void **out)
{
    Ctx *c = (Ctx *)ud;
    if (c->pos >= c->nx) return 0;
    *out = pack(c->xs[c->pos++]);
    return 1;
}

static void ctx_emit(void *ud, void *elem)
{
    Ctx *c = (Ctx *)ud;
    if (c->res_len == c->res_cap) {
        c->res_cap = c->res_cap ? c->res_cap * 2 : 8;
        c->results = (int *)realloc(c->results,
                                    (size_t)c->res_cap * sizeof(int));
    }
    c->results[c->res_len++] = unpack(elem);
}

static void *ctx_op(void *ud, void *a, void *b)
{
    Ctx *c  = (Ctx *)ud;
    int  ia = unpack(a), ib = unpack(b);
    int  v;
    switch (c->op_kind) {
    case 1:  v = ia > ib ? ia : ib; break;  /* max */
    case 2:  v = ia < ib ? ia : ib; break;  /* min */
    default: v = ia + ib;           break;  /* add */
    }
    return pack(v);
}

/* ── run helper ──────────────────────────────────────────────────────── */

/**
 * Run the sliding-window algorithm over `xs[0..nx-1]` for the given
 * windows, using the operator identified by op_kind (0=add,1=max,2=min).
 * Returns a heap-allocated array of results; caller must free it.
 * *out_len is set to the number of results.
 */
static int *run(int op_kind,
                const int *xs, int nx,
                const SW_Window *ws, int nw,
                int *out_len)
{
    Ctx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.xs      = xs;
    ctx.nx      = nx;
    ctx.op_kind = op_kind;

    SW_State *sw = sw_create(ctx_next, ctx_emit, ctx_op, NULL, &ctx);
    for (int i = 0; i < nw; i++)
        sw_slide(sw, ws[i]);
    sw_destroy(sw);

    *out_len = ctx.res_len;
    return ctx.results;   /* caller frees */
}

/* ────────────────────────────────────────────────────────────────────
 * Individual tests
 * ──────────────────────────────────────────────────────────────────── */

static void test_single_window(void)
{
    printf("\n[test_single_window]\n");
    const int xs[] = { 1, 2, 3, 4, 5 };
    SW_Window ws[] = { {0, 4} };
    int n; int *r = run(0, xs, 5, ws, 1, &n);
    CHECK(n == 1,        "result count == 1");
    CHECK(r[0] == 15,    "sum(0..4) == 15");
    free(r);
}

static void test_fixed_size_window_sum(void)
{
    printf("\n[test_fixed_size_window_sum]\n");
    /* sliding window of size 3: sums 6, 9, 12 */
    const int xs[] = { 1, 2, 3, 4, 5 };
    SW_Window ws[] = { {0,2}, {1,3}, {2,4} };
    int n; int *r = run(0, xs, 5, ws, 3, &n);
    CHECK(n == 3,        "result count == 3");
    CHECK(r[0] ==  6,    "sum(0..2) == 6");
    CHECK(r[1] ==  9,    "sum(1..3) == 9");
    CHECK(r[2] == 12,    "sum(2..4) == 12");
    free(r);
}

static void test_variable_size_window(void)
{
    printf("\n[test_variable_size_window]\n");
    const int xs[] = { 3, 1, 4, 1, 5, 9, 2, 6 };
    SW_Window ws[] = { {0,1}, {0,3}, {2,5}, {3,7} };
    /* 3+1=4, 3+1+4+1=9, 4+1+5+9=19, 1+5+9+2+6=23 */
    int n; int *r = run(0, xs, 8, ws, 4, &n);
    CHECK(n == 4,        "result count == 4");
    CHECK(r[0] ==  4,    "sum(0..1) == 4");
    CHECK(r[1] ==  9,    "sum(0..3) == 9");
    CHECK(r[2] == 19,    "sum(2..5) == 19");
    CHECK(r[3] == 23,    "sum(3..7) == 23");
    free(r);
}

static void test_max_operator(void)
{
    printf("\n[test_max_operator]\n");
    const int xs[] = { 3, 1, 4, 1, 5, 9, 2, 6 };
    SW_Window ws[] = { {0,2}, {1,4}, {3,7} };
    int n; int *r = run(1, xs, 8, ws, 3, &n);
    CHECK(n == 3,      "result count == 3");
    CHECK(r[0] == 4,   "max(0..2) == 4");
    CHECK(r[1] == 5,   "max(1..4) == 5");
    CHECK(r[2] == 9,   "max(3..7) == 9");
    free(r);
}

static void test_min_operator(void)
{
    printf("\n[test_min_operator]\n");
    const int xs[] = { 5, 3, 8, 1, 4 };
    SW_Window ws[] = { {0,1},{1,2},{2,4},{0,4} };
    int n; int *r = run(2, xs, 5, ws, 4, &n);
    CHECK(n == 4,      "result count == 4");
    CHECK(r[0] == 3,   "min(0..1) == 3");
    CHECK(r[1] == 3,   "min(1..2) == 3");
    CHECK(r[2] == 1,   "min(2..4) == 1");
    CHECK(r[3] == 1,   "min(0..4) == 1");
    free(r);
}

static void test_singleton_elements(void)
{
    printf("\n[test_singleton_elements]\n");
    const int xs[] = { 7, 3, 9, 2 };
    SW_Window ws[] = { {0,0},{1,1},{2,2},{3,3} };
    int n; int *r = run(0, xs, 4, ws, 4, &n);
    CHECK(n == 4,      "result count == 4");
    CHECK(r[0] == 7,   "xs[0] == 7");
    CHECK(r[1] == 3,   "xs[1] == 3");
    CHECK(r[2] == 9,   "xs[2] == 9");
    CHECK(r[3] == 2,   "xs[3] == 2");
    free(r);
}

static void test_growing_window(void)
{
    printf("\n[test_growing_window]\n");
    /* prefix sums */
    const int xs[] = { 1, 2, 3, 4, 5 };
    SW_Window ws[] = { {0,0},{0,1},{0,2},{0,3},{0,4} };
    int n; int *r = run(0, xs, 5, ws, 5, &n);
    CHECK(n == 5,       "result count == 5");
    CHECK(r[0] ==  1,   "prefix[0] == 1");
    CHECK(r[1] ==  3,   "prefix[1] == 3");
    CHECK(r[2] ==  6,   "prefix[2] == 6");
    CHECK(r[3] == 10,   "prefix[3] == 10");
    CHECK(r[4] == 15,   "prefix[4] == 15");
    free(r);
}

static void test_shrinking_left(void)
{
    printf("\n[test_shrinking_left]\n");
    /* suffix sums */
    const int xs[] = { 1, 2, 3, 4, 5 };
    SW_Window ws[] = { {0,4},{1,4},{2,4},{3,4},{4,4} };
    int n; int *r = run(0, xs, 5, ws, 5, &n);
    CHECK(n == 5,       "result count == 5");
    CHECK(r[0] == 15,   "suffix[0] == 15");
    CHECK(r[1] == 14,   "suffix[1] == 14");
    CHECK(r[2] == 12,   "suffix[2] == 12");
    CHECK(r[3] ==  9,   "suffix[3] == 9");
    CHECK(r[4] ==  5,   "suffix[4] == 5");
    free(r);
}

static void test_gap_between_windows(void)
{
    printf("\n[test_gap_between_windows]\n");
    const int xs[] = { 0,1,2,3,4,5,6,7,8,9 };
    SW_Window ws[] = { {0,1},{5,7},{8,9} };
    /* 0+1=1, 5+6+7=18, 8+9=17 */
    int n; int *r = run(0, xs, 10, ws, 3, &n);
    CHECK(n == 3,       "result count == 3");
    CHECK(r[0] ==  1,   "sum(0..1) == 1");
    CHECK(r[1] == 18,   "sum(5..7) == 18");
    CHECK(r[2] == 17,   "sum(8..9) == 17");
    free(r);
}

static void test_no_windows(void)
{
    printf("\n[test_no_windows]\n");
    const int xs[] = { 1, 2, 3 };
    int n; int *r = run(0, xs, 3, NULL, 0, &n);
    CHECK(n == 0, "no windows → no results");
    free(r);
}

static void test_large_stream_fixed_window(void)
{
    printf("\n[test_large_stream_fixed_window]\n");
    const int N = 1000, W = 10;

    int *xs = (int *)malloc((size_t)N * sizeof(int));
    for (int i = 0; i < N; i++) xs[i] = i + 1;

    int nw = N - W + 1;
    SW_Window *ws = (SW_Window *)malloc((size_t)nw * sizeof(SW_Window));
    for (int i = 0; i < nw; i++) { ws[i].left = i; ws[i].right = i + W - 1; }

    int n; int *r = run(0, xs, N, ws, nw, &n);
    CHECK(n == nw, "result count == 991");

    int ok = 1;
    for (int i = 0; i < nw; i++) {
        /* sum of (i+1)..(i+W) = W*i + W*(W+1)/2 */
        int expected = W * i + W * (W + 1) / 2;
        if (r[i] != expected) { ok = 0; break; }
    }
    CHECK(ok, "all sliding sums correct");

    free(xs); free(ws); free(r);
}

static void test_overlapping_windows(void)
{
    printf("\n[test_overlapping_windows]\n");
    /*
     * Windows must satisfy l non-decreasing AND r non-decreasing.
     * This tests heavily overlapping but valid window sequences.
     */
    const int xs[] = { 2, 4, 6, 8, 10 };
    /* l: 0,1,1,2,3  r: 4,4,4,4,4  – both non-decreasing */
    SW_Window ws[] = { {0,4},{1,4},{1,4},{2,4},{3,4} };
    int n; int *r = run(0, xs, 5, ws, 5, &n);
    CHECK(n == 5,        "result count == 5");
    CHECK(r[0] == 30,    "sum(0..4)==30");
    CHECK(r[1] == 28,    "sum(1..4)==28");
    CHECK(r[2] == 28,    "sum(1..4)==28 (repeated window)");
    CHECK(r[3] == 24,    "sum(2..4)==24");
    CHECK(r[4] == 18,    "sum(3..4)==18");
    free(r);
}

/* ────────────────────────────────────────────────────────────────────
 * main
 * ──────────────────────────────────────────────────────────────────── */

int main(void)
{
    printf("=== Sliding Window (C) – unit tests ===\n");

    test_single_window();
    test_fixed_size_window_sum();
    test_variable_size_window();
    test_max_operator();
    test_min_operator();
    test_singleton_elements();
    test_growing_window();
    test_shrinking_left();
    test_gap_between_windows();
    test_no_windows();
    test_large_stream_fixed_window();
    test_overlapping_windows();

    printf("\n=== Results: %d passed, %d failed ===\n", g_passed, g_failed);
    return g_failed ? 1 : 0;
}
