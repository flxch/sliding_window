/**
 * sliding_window.h  –  Greedy sliding-window aggregation (C99)
 *
 * Based on:
 *   D. Basin, F. Klaedtke, and E. Zalinescu.
 *   Greedily Computing Associative Aggregations on Sliding Windows.
 *   Information Processing Letters, 115(2):186-192, 2015.
 *
 * Design choices vs. the Go implementation
 * ─────────────────────────────────────────
 * Go uses goroutines + channels for streaming.  In C we expose a
 * callback / function-pointer interface instead:
 *
 *   • next_element_fn   – called whenever the algorithm needs the next
 *                         stream element; returns 1 on success, 0 when
 *                         the stream is exhausted.
 *   • emit_result_fn    – called with each computed window aggregate.
 *
 * This keeps the implementation fully synchronous and avoids the need
 * for threads or OS-level I/O, while still supporting infinite streams
 * (elements are consumed lazily, just as with channels in Go).
 *
 * Memory management
 * ─────────────────
 * Tree nodes are allocated with malloc and freed as soon as they are
 * no longer reachable (i.e. when a subtree is replaced during slide).
 * The public API owns no persistent heap storage between calls; all
 * state is inside the opaque `SW_State` struct.
 */

#ifndef SLIDING_WINDOW_H
#define SLIDING_WINDOW_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── callback types ───────────────────────────────────────────────── */

/**
 * Called to fetch the next element from the input stream.
 * Write the element into *out_elem.
 * Return 1 if an element was produced, 0 if the stream is exhausted.
 * `user_data` is the pointer supplied to sw_create().
 */
typedef int  (*SW_NextFn)(void *user_data, void **out_elem);

/**
 * Called to deliver a computed aggregate to the consumer.
 * `elem`      – the aggregated value (owned by the caller; copy if needed).
 * `user_data` – the pointer supplied to sw_create().
 */
typedef void (*SW_EmitFn)(void *user_data, void *elem);

/**
 * The associative binary operator.
 * Both arguments are guaranteed non-NULL.
 * The return value must be a newly allocated (or static) value that the
 * algorithm may later pass back into `op` or into `emit`.
 * `user_data` – the pointer supplied to sw_create().
 */
typedef void *(*SW_OpFn)(void *user_data, void *a, void *b);

/**
 * Free a value that was returned by SW_OpFn.
 * May be NULL if values need not be freed (e.g. they are integers cast
 * to void*).
 */
typedef void (*SW_FreeFn)(void *user_data, void *elem);

/* ── window type ──────────────────────────────────────────────────── */

typedef struct {
    int left;   /* inclusive, 0-based */
    int right;  /* inclusive, 0-based, right >= left */
} SW_Window;

/* ── opaque state ─────────────────────────────────────────────────── */

typedef struct SW_State SW_State;

/* ── public API ───────────────────────────────────────────────────── */

/**
 * Create a new sliding-window state object.
 *
 * @param next      callback to fetch input elements
 * @param emit      callback to deliver results
 * @param op        associative binary operator
 * @param free_fn   destructor for values returned by op (may be NULL)
 * @param user_data opaque pointer forwarded to every callback
 * @return          heap-allocated state (free with sw_destroy)
 */
SW_State *sw_create(SW_NextFn  next,
                    SW_EmitFn  emit,
                    SW_OpFn    op,
                    SW_FreeFn  free_fn,
                    void      *user_data);

/**
 * Feed one window to the algorithm.
 *
 * Windows must satisfy:
 *   l_0 <= l_1 <= ... and r_0 <= r_1 <= ... and 0 <= l_i <= r_i
 *
 * Reads stream elements as needed via `next`, then calls `emit` with
 * the aggregate for the window.
 *
 * @return  1 on success, 0 if the stream was exhausted before the
 *          window could be fully evaluated.
 */
int sw_slide(SW_State *s, SW_Window w);

/**
 * Destroy state and free all internal memory.
 * Values stored inside tree nodes are freed via the `free_fn` callback.
 */
void sw_destroy(SW_State *s);

#ifdef __cplusplus
}
#endif

#endif /* SLIDING_WINDOW_H */
