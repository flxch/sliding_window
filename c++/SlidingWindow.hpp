/**
 * SlidingWindow.hpp  –  Greedy sliding-window aggregation (C++17)
 *
 * Based on:
 *   D. Basin, F. Klaedtke, and E. Zalinescu.
 *   Greedily Computing Associative Aggregations on Sliding Windows.
 *   Information Processing Letters, 115(2):186-192, 2015.
 *
 * Stream I/O model
 * ────────────────
 * Instead of Go channels this implementation uses two callables:
 *   Generator  std::function<std::optional<T>()>
 *     – called to pull the next stream element lazily; returns
 *       std::nullopt when the stream is exhausted.
 *   Sink       std::function<void(const T&)>
 *     – called with each computed window aggregate.
 *
 * Both can be backed by anything: vectors, files, sockets, coroutines,
 * infinite sequences, …  Elements are consumed lazily, one window at a
 * time, matching the pull-based behaviour of Go channels.
 *
 * Memory management
 * ─────────────────
 * Tree nodes are heap-allocated and owned by std::unique_ptr.  When a
 * unique_ptr is reset or goes out of scope the node (and its value T)
 * are destroyed automatically – no manual free() required.
 *
 * The same structural invariant as in the C version applies:
 *   A discharged node (agg == nullopt) that still has live children
 *   must NOT be freed because reusables() navigates through it.
 * See prune_discharged() below.
 */

#pragma once

#include <cassert>
#include <functional>
#include <memory>
#include <optional>
#include <vector>

namespace sw {

// ── Window ─────────────────────────────────────────────────────────────

struct Window {
    int left;   ///< inclusive, 0-based
    int right;  ///< inclusive, 0-based; right >= left
};

// ── SlidingWindow ──────────────────────────────────────────────────────

/**
 * Computes aggregations of stream elements within sliding windows for an
 * associative operator.
 *
 * @tparam T   element type; must be copyable/movable.
 * @tparam Op  binary operator (T,T)->T; assumed associative.
 */
template <typename T,
          typename Op = std::function<T(const T&, const T&)>>
class SlidingWindow {
public:
    using Generator = std::function<std::optional<T>()>;
    using Sink      = std::function<void(const T&)>;

    /**
     * @param gen   callable returning the next stream element, or nullopt.
     * @param sink  called with each computed aggregate.
     * @param op    associative binary operator.
     */
    SlidingWindow(Generator gen, Sink sink, Op op)
        : gen_(std::move(gen))
        , sink_(std::move(sink))
        , op_(std::move(op))
        , tree_(nullptr)
    {}

    /**
     * Advance the algorithm by one window step.
     * Reads stream elements as needed, then calls the sink with the result.
     *
     * @return true on success; false if the stream was exhausted before
     *         the window could be fully evaluated.
     */
    bool slide(Window w);

private:
    // ── internal binary-tree node ───────────────────────────────────────

    struct Node {
        int              from;   ///< left  index of covered range
        int              to;     ///< right index of covered range
        std::optional<T> agg;    ///< aggregated value; nullopt = discharged

        std::unique_ptr<Node> left;
        std::unique_ptr<Node> right;

        Node(int f, int t, std::optional<T> a)
            : from(f), to(t), agg(std::move(a)) {}

        // Nodes are not copyable; unique_ptr children enforce move-only.
        Node(const Node&)            = delete;
        Node& operator=(const Node&) = delete;
    };

    using NodePtr = std::unique_ptr<Node>;

    // ── state ───────────────────────────────────────────────────────────

    Generator gen_;
    Sink      sink_;
    Op        op_;
    NodePtr   tree_;   ///< current aggregation tree; nullptr = empty

    // ── node helpers ────────────────────────────────────────────────────

    static int right_index(const NodePtr& t) noexcept
    {
        return t ? t->to : -1;
    }

    static NodePtr make_singleton(T x, int i)
    {
        return std::make_unique<Node>(i, i, std::optional<T>(std::move(x)));
    }

    /** Clear the node's cached aggregation. */
    static void discharge(Node* t) noexcept
    {
        if (t) t->agg.reset();
    }

    /**
     * combine(t1, t2)  –  merge two sub-trees.
     *
     * If either argument is null, the other is returned unchanged.
     * Otherwise a new parent node is created spanning [t1->from, t2->to]
     * with agg = op(t1->agg, t2->agg); t1 is discharged and becomes the
     * left child, t2 becomes the right child.
     */
    NodePtr combine(NodePtr t1, NodePtr t2)
    {
        if (!t1) return t2;
        if (!t2) return t1;

        T v = op_(*t1->agg, *t2->agg);
        discharge(t1.get());   // t1's value is now encoded in v

        auto n    = std::make_unique<Node>(t1->from, t2->to,
                                           std::optional<T>(std::move(v)));
        n->left   = std::move(t1);
        n->right  = std::move(t2);
        return n;
    }

    /**
     * prune_discharged(t)  –  reclaim truly dead nodes.
     *
     * A discharged node (agg == nullopt) that still has live children must
     * NOT be freed – reusables() uses it as a structural guide.  Only a
     * discharged node with no surviving children is safe to destroy.
     */
    static NodePtr prune_discharged(NodePtr t)
    {
        if (!t) return nullptr;

        // Always prune children first so we know whether they survive.
        t->left  = prune_discharged(std::move(t->left));
        t->right = prune_discharged(std::move(t->right));

        if (t->agg)
            return t;   // live – keep

        // Discharged: keep as structural placeholder if children survive.
        if (t->left || t->right)
            return t;

        return nullptr;  // unique_ptr destructor frees the dead node
    }

    /**
     * do_reusables(t, l, acc)  –  iterative implementation of reusables().
     *
     * Folds every maximal subtree of `t` whose full index range lies at or
     * to the right of `l` into `acc` via combine().
     *
     * Ownership / memory:
     *   When the loop descends past a parent node, that node and any
     *   descendants strictly left of `l` are unreachable from the result
     *   and are freed by resetting their unique_ptrs before continuing.
     */
    NodePtr do_reusables(NodePtr t, int l, NodePtr acc)
    {
        for (;;) {
            if (!t) return acc;
            if (l > t->to) {
                // Entire subtree t is strictly left of l – not reusable.
                // Resetting the unique_ptr deep-frees the whole subtree.
                t.reset();
                return acc;
            }
            if (l == t->from) return combine(std::move(t), std::move(acc));

            const int t_right_from = t->right ? t->right->from : -1;

            if (t->right && l >= t_right_from) {
                // l falls within t->right's range.
                // t->left (entirely left of l) is no longer reusable – drop it.
                // Move t->right out, then let t (now childless) be destroyed.
                NodePtr right_child = std::move(t->right);
                t->left.reset();   // deep-frees the unreusable left subtree
                // t falls out of scope here (its unique_ptr is overwritten next)
                t = std::move(right_child);
            } else {
                // t->right is fully at or above l – incorporate into acc.
                // Move both children out before t is destroyed.
                NodePtr right_child = std::move(t->right);
                NodePtr left_child  = std::move(t->left);
                // t falls out of scope (overwritten by move below)
                acc = combine(std::move(right_child), std::move(acc));
                t   = std::move(left_child);
            }
        }
    }

    /**
     * read_and_fold(from, n, acc, out)
     *
     * Pull `n` stream elements starting at index `from`, build singleton
     * nodes, and fold them right-to-left into `acc`.
     *
     * Right-to-left folding: element at `from` ends up deepest on the left
     * spine, matching the reversed-list fold in the reference impls.
     *
     * Returns true on success, false if the stream closes early.
     */
    bool read_and_fold(int from, int n, NodePtr acc, NodePtr& out)
    {
        if (n <= 0) { out = std::move(acc); return true; }

        std::vector<NodePtr> buf;
        buf.reserve(static_cast<size_t>(n));
        bool ok = true;

        for (int k = 0; k < n; k++) {
            auto elem = gen_();
            if (!elem) { ok = false; break; }
            buf.push_back(make_singleton(std::move(*elem), from + k));
        }

        // Fold right-to-left: iterate buffer in reverse
        NodePtr result = std::move(acc);
        for (int k = static_cast<int>(buf.size()) - 1; k >= 0; k--)
            result = combine(std::move(buf[k]), std::move(result));

        out = std::move(result);
        return ok;
    }

    /**
     * do_slide(w)  –  one window step; updates tree_.
     */
    bool do_slide(Window w)
    {
        const int l          = w.left;
        const int r          = w.right;
        const int prev_right = right_index(tree_);   // -1 when empty

        // First index needed from the stream for this window
        const int new_from = (l > prev_right + 1) ? l : prev_right + 1;

        // Skip stream elements that fall in the gap between windows
        const int skip = new_from - (prev_right + 1);
        for (int k = 0; k < skip; k++) {
            if (!gen_()) return false;
        }

        // Read new elements and build a partial tree
        const int n_new = std::max(0, r - new_from + 1);

        NodePtr new_part;
        if (!read_and_fold(new_from, n_new, nullptr, new_part))
            return false;

        // Fold in reusable subtrees from the previous tree
        NodePtr result = do_reusables(std::move(tree_), l, std::move(new_part));

        // Reclaim discharged / dead nodes
        tree_ = prune_discharged(std::move(result));
        return true;
    }
};

// ── slide() ────────────────────────────────────────────────────────────

template <typename T, typename Op>
bool SlidingWindow<T, Op>::slide(Window w)
{
    if (!do_slide(w))
        return false;

    assert(tree_ && tree_->agg && "tree must have a valid agg after slide");
    sink_(*tree_->agg);
    return true;
}

// ── convenience factory ────────────────────────────────────────────────

/**
 * Deduce template parameters from arguments.
 *
 *   auto sw = sw::make_sliding_window<int>(gen, sink,
 *                 [](int a, int b){ return a+b; });
 */
template <typename T, typename Op>
auto make_sliding_window(
    std::function<std::optional<T>()> gen,
    std::function<void(const T&)>     sink,
    Op                                op)
{
    return SlidingWindow<T, Op>(std::move(gen), std::move(sink), std::move(op));
}

} // namespace sw
