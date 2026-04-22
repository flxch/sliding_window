/**
 * sliding_window.c  –  Greedy sliding-window aggregation (C99)
 *
 * Based on:
 *   D. Basin, F. Klaedtke, and E. Zalinescu.
 *   Greedily Computing Associative Aggregations on Sliding Windows.
 *   Information Processing Letters, 115(2):186-192, 2015.
 *
 * Stream I/O model
 * ────────────────
 * Go uses channels.  Here we use callbacks (function pointers):
 *   • SW_NextFn   – called to pull the next element from the stream.
 *   • SW_EmitFn   – called to push each computed window aggregate.
 *   • SW_OpFn     – the associative binary operator.
 *   • SW_FreeFn   – destructor for values produced by SW_OpFn.
 *
 * This keeps the implementation single-threaded and supports infinite
 * streams because elements are consumed lazily (one window at a time).
 *
 * Memory management
 * ─────────────────
 * Tree nodes are malloc'd in make_singleton() and combine(), and freed:
 *   • lazily via prune_discharged() after each slide step, and
 *   • completely via free_tree() in sw_destroy().
 *
 * Aggregation values produced by SW_OpFn are freed via SW_FreeFn.
 * User-supplied element pointers (from SW_NextFn) are never freed.
 */

#include "sliding_window.h"

#include <assert.h>
#include <stdlib.h>

/* ────────────────────────────────────────────────────────────────────
 * Internal binary-tree node
 * ──────────────────────────────────────────────────────────────────── */
typedef struct Node {
    int          from;        /* left  index of covered range          */
    int          to;          /* right index of covered range          */
    void        *agg;         /* aggregated value; NULL when discharged */
    int          user_owned;  /* 1 → agg is user data; never free it   */
    struct Node *left;
    struct Node *right;
} Node;

/* ────────────────────────────────────────────────────────────────────
 * Opaque state
 * ──────────────────────────────────────────────────────────────────── */
struct SW_State {
    SW_NextFn  next;
    SW_EmitFn  emit;
    SW_OpFn    op;
    SW_FreeFn  free_fn;
    void      *user_data;
    Node      *tree;      /* root of current aggregation tree; NULL = empty */
};

/* ────────────────────────────────────────────────────────────────────
 * Node constructors / selectors
 * ──────────────────────────────────────────────────────────────────── */

static int right_index(const Node *t) { return t ? t->to   : -1; }

/* Singleton node for user element `x` at stream index `i`. */
static Node *make_singleton(void *x, int i)
{
    Node *n      = (Node *)malloc(sizeof(Node));
    n->from      = i;
    n->to        = i;
    n->agg       = x;
    n->user_owned = 1;   /* user owns this pointer */
    n->left      = NULL;
    n->right     = NULL;
    return n;
}

/* ────────────────────────────────────────────────────────────────────
 * discharge(s, t)
 *
 * Invalidate t's cached aggregation value.  If the value was produced
 * by SW_OpFn (i.e. !user_owned) it is freed via free_fn.
 * ──────────────────────────────────────────────────────────────────── */
static void discharge(SW_State *s, Node *t)
{
    if (!t) return;
    if (!t->user_owned && t->agg && s->free_fn)
        s->free_fn(s->user_data, t->agg);
    t->agg        = NULL;
    t->user_owned = 0;
}

/* ────────────────────────────────────────────────────────────────────
 * combine(s, t1, t2)
 *
 * Merge two sub-trees.  If either is NULL the other is returned as-is.
 * Otherwise create a new parent node spanning [t1->from, t2->to] with
 * agg = op(t1->agg, t2->agg), discharge t1 (its value is now in agg),
 * and set t1 / t2 as left / right children.
 * ──────────────────────────────────────────────────────────────────── */
static Node *combine(SW_State *s, Node *t1, Node *t2)
{
    if (!t1) return t2;
    if (!t2) return t1;

    void *v = s->op(s->user_data, t1->agg, t2->agg);

    discharge(s, t1);   /* t1's value is now encoded in v */

    Node *n       = (Node *)malloc(sizeof(Node));
    n->from       = t1->from;
    n->to         = t2->to;
    n->agg        = v;
    n->user_owned = 0;
    n->left       = t1;
    n->right      = t2;
    return n;
}

/* ────────────────────────────────────────────────────────────────────
 * prune_discharged(t)
 *
 * Post-order walk: free every node whose agg == NULL.  Such nodes have
 * given their value to a parent and carry no useful data any more.
 * Returns the (possibly-changed) root pointer.
 * ──────────────────────────────────────────────────────────────────── */
static Node *prune_discharged(Node *t)
{
    if (!t) return NULL;

    /* Always recurse first so children are pruned before we decide. */
    t->left  = prune_discharged(t->left);
    t->right = prune_discharged(t->right);

    if (t->agg)
        return t;   /* live node - keep */

    /* Discharged node: only reclaim it when it has NO live children.
     *
     * Even though a discharged node has no agg of its own, its subtree
     * may still hold live values that reusables() must traverse in
     * future slide steps.  Freeing such a node would orphan those
     * descendants and corrupt the traversal.
     *
     * A discharged node with surviving children is kept as a structural
     * placeholder.  It will be freed once all its descendants are gone.
     */
    if (t->left || t->right)
        return t;

    /* No agg, no children: truly dead - reclaim it. */
    free(t);
    return NULL;
}

/* ────────────────────────────────────────────────────────────────────
 * free_tree(s, t)  –  deep free; used in sw_destroy.
 * ──────────────────────────────────────────────────────────────────── */
static void free_tree(SW_State *s, Node *t)
{
    if (!t) return;
    free_tree(s, t->left);
    free_tree(s, t->right);
    if (!t->user_owned && t->agg && s->free_fn)
        s->free_fn(s->user_data, t->agg);
    free(t);
}

/* ────────────────────────────────────────────────────────────────────
 * do_reusables(s, t, l, acc)
 *
 * Iterative implementation.  Folds every maximal subtree of `t` whose
 * full index range lies at or to the right of `l` into `acc` via
 * combine().  This mirrors the reference reusables() function exactly.
 *
 * Memory:
 *   When we descend past a parent node `t`, that node is no longer
 *   reachable from the result and must be freed:
 *
 *   • "descend right" branch: l falls entirely within t->right's range.
 *     t->left and all its descendants are strictly left of l and will
 *     never be reused – free them.  Then free the shell of t itself
 *     (its agg is already NULL from discharge; it was an intermediate
 *     node).  Set t = t_right and continue.
 *
 *   • "combine right, descend left" branch: t->right is incorporated
 *     into acc via combine.  The shell of t is again dead; free it.
 *     Set t = t_left and continue.
 *
 *   In both cases we save the child pointers before freeing t.
 * ──────────────────────────────────────────────────────────────────── */
static Node *do_reusables(SW_State *s, Node *t, int l, Node *acc)
{
    for (;;) {
        if (!t)        return acc;
        if (l > t->to) {
            /* Entire subtree t is strictly left of l – not reusable.
             * Free it all and return. */
            free_tree(s, t);
            return acc;
        }
        if (l == t->from) return combine(s, t, acc);

        Node *t_left  = t->left;
        Node *t_right = t->right;

        if (t_right && l >= t_right->from) {
            /* l is within t_right's range; t_left is entirely below l. */
            free_tree(s, t_left);   /* not reusable; free subtree       */
            free(t);                /* free the now-childless shell      */
            t = t_right;
        } else {
            /* t_right is fully at or above l; incorporate it into acc. */
            acc = combine(s, t_right, acc);
            free(t);                /* t_right moved into acc; shell dead */
            t = t_left;
        }
    }
}

/* ────────────────────────────────────────────────────────────────────
 * read_and_fold(s, from, n, acc, out)
 *
 * Pull `n` elements from the stream starting at global index `from`,
 * wrap each in a singleton node, then fold them right-to-left into
 * `acc` via combine().
 *
 * Right-to-left folding: element `from` ends up deepest on the left
 * spine, matching the `foldl (swap combine) Leaf (reverse news ++ reuses)`
 * idiom in the Haskell reference.
 *
 * Returns 1 on success, 0 if the stream closes early.
 * ──────────────────────────────────────────────────────────────────── */
static int read_and_fold(SW_State *s, int from, int n, Node *acc, Node **out)
{
    if (n <= 0) { *out = acc; return 1; }

    /* Collect singletons into a temporary buffer so we can fold
       right-to-left without recursion. */
    Node **buf    = (Node **)malloc((size_t)n * sizeof(Node *));
    int collected = 0, ok = 1;

    for (int k = 0; k < n; k++) {
        void *elem = NULL;
        if (!s->next(s->user_data, &elem)) { ok = 0; break; }
        buf[collected++] = make_singleton(elem, from + k);
    }

    Node *result = acc;
    for (int k = collected - 1; k >= 0; k--)
        result = combine(s, buf[k], result);

    free(buf);
    *out = result;
    return ok;
}

/* ────────────────────────────────────────────────────────────────────
 * do_slide(s, w)  –  one window step.
 *
 * Mirrors slide() from the Go implementation.
 *
 *   from   = first index needed from the stream for this window
 *   n_new  = number of new elements to read
 *   skip   = elements between the previous window and `from` that we
 *             must consume from the stream but do not aggregate
 * ──────────────────────────────────────────────────────────────────── */
static int do_slide(SW_State *s, SW_Window w)
{
    int l          = w.left;
    int r          = w.right;
    int prev_right = right_index(s->tree);   /* -1 when tree is empty */

    /* first index needed for this window that hasn't been read yet */
    int new_from = (l > prev_right + 1) ? l : prev_right + 1;

    /* skip elements that fall in the gap between the two windows */
    int skip = new_from - (prev_right + 1);
    for (int k = 0; k < skip; k++) {
        void *dummy = NULL;
        if (!s->next(s->user_data, &dummy)) return 0;
    }

    /* read new elements and build a partial tree */
    int   n_new   = r - new_from + 1;
    if (n_new < 0) n_new = 0;

    Node *new_part = NULL;
    if (!read_and_fold(s, new_from, n_new, NULL, &new_part))
        return 0;

    /* fold in reusable subtrees from the previous tree */
    Node *result = do_reusables(s, s->tree, l, new_part);

    /* reclaim discharged (value-less) nodes */
    s->tree = prune_discharged(result);
    return 1;
}

/* ────────────────────────────────────────────────────────────────────
 * Public API
 * ──────────────────────────────────────────────────────────────────── */

SW_State *sw_create(SW_NextFn  next,
                    SW_EmitFn  emit,
                    SW_OpFn    op,
                    SW_FreeFn  free_fn,
                    void      *user_data)
{
    SW_State *s  = (SW_State *)malloc(sizeof(SW_State));
    s->next      = next;
    s->emit      = emit;
    s->op        = op;
    s->free_fn   = free_fn;
    s->user_data = user_data;
    s->tree      = NULL;
    return s;
}

int sw_slide(SW_State *s, SW_Window w)
{
    if (!do_slide(s, w))
        return 0;

    assert(s->tree && s->tree->agg);
    s->emit(s->user_data, s->tree->agg);
    return 1;
}

void sw_destroy(SW_State *s)
{
    if (!s) return;
    free_tree(s, s->tree);
    free(s);
}
