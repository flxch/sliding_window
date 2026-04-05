//! Greedy sliding-window aggregation over a data stream.
//!
//! This implements the algorithm described in:
//!
//!   D. Basin, F. Klaedtke, and E. Zalinescu.
//!   *Greedily Computing Associative Aggregations on Sliding Windows.*
//!   Information Processing Letters, 115(2):186–192, 2015.
//!
//! The algorithm computes, for each window `[l_i, r_i]` in a monotonically
//! advancing sequence of windows over an input stream, the value
//!
//! ```text
//! x[l_i] op x[l_i+1] op … op x[r_i]
//! ```
//!
//! using a minimal number of applications of the associative operator `op`.
//!
//! # Design
//!
//! The Go reference implementation uses channels (`chan`) for the input stream
//! and for output.  In Rust the idiomatic equivalent is an [`Iterator`]: lazy,
//! composable, and zero-cost.  The public API therefore exposes
//! [`SlidingWindow`], which is itself an iterator that wraps
//!
//! * an **input iterator** – the source of stream elements, and
//! * a **windows iterator** – the source of `(left, right)` windows.
//!
//! Calling [`Iterator::next`] on a [`SlidingWindow`] advances one window step
//! and returns the aggregated value for that window, mirroring the Go
//! `SlidingWindow` function but without requiring any threads or channels.

/// A half-open window `[left, right]` (both bounds inclusive) over a stream.
///
/// Invariants (caller's responsibility):
/// * `0 <= left <= right`
/// * Both `left` and `right` sequences must be non-decreasing across windows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Window {
    pub left: usize,
    pub right: usize,
}

// ---------------------------------------------------------------------------
// Internal tree representation
// ---------------------------------------------------------------------------

/// An aggregated value that may or may not have been computed yet.
///
/// `None` means the node has been *discharged* – its subtree is still in
/// the tree for structural reasons but its pre-computed aggregate has been
/// cleared to avoid stale reads.
type Agg<A> = Option<A>;

/// A node in the binary aggregation tree.
///
/// Every non-leaf node covers the index range `[from, to]` in the stream.
/// The `aggregation` field is `Some(v)` when the combined value for that
/// range is available and `None` after the node has been discharged.
#[derive(Debug, Clone)]
struct Node<A> {
    from: usize,
    to: usize,
    aggregation: Agg<A>,
}

/// A binary tree whose leaves carry no data and whose inner nodes carry a
/// [`Node`].
///
/// We represent the tree as a heap-allocated, owned value (boxing children)
/// so that combine / discharge can be done without copying large subtrees.
/// A `None` variant is the leaf (analogous to `Leaf` in the Haskell/OCaml
/// implementations and the sentinel `t.left == nil` check in Go).
#[derive(Debug, Clone)]
enum Tree<A> {
    Leaf,
    Inner {
        node: Node<A>,
        left: Box<Tree<A>>,
        right: Box<Tree<A>>,
    },
}

impl<A: Clone> Tree<A> {
    // ------------------------------------------------------------------
    // Constructors
    // ------------------------------------------------------------------

    /// Creates a singleton tree covering exactly index `i` with value `x`.
    fn singleton(i: usize, x: A) -> Self {
        Tree::Inner {
            node: Node {
                from: i,
                to: i,
                aggregation: Some(x),
            },
            left: Box::new(Tree::Leaf),
            right: Box::new(Tree::Leaf),
        }
    }

    // ------------------------------------------------------------------
    // Selectors
    // ------------------------------------------------------------------

    /// Returns the leftmost index covered by this tree, or `None` for a leaf.
    fn left_index(&self) -> Option<usize> {
        match self {
            Tree::Leaf => None,
            Tree::Inner { node, .. } => Some(node.from),
        }
    }

    /// Returns the rightmost index covered by this tree, or `None` for a leaf.
    fn right_index(&self) -> Option<usize> {
        match self {
            Tree::Leaf => None,
            Tree::Inner { node, .. } => Some(node.to),
        }
    }

    /// Returns `true` when this is a leaf (no children, no data).
    fn is_leaf(&self) -> bool {
        matches!(self, Tree::Leaf)
    }

    /// Extracts the aggregated value at the root.
    ///
    /// # Panics
    /// Panics if called on a leaf or on a discharged node.
    fn extract(&self) -> &A {
        match self {
            Tree::Leaf => panic!("extract: called on a leaf"),
            Tree::Inner { node, .. } => node
                .aggregation
                .as_ref()
                .expect("extract: aggregation has been discharged"),
        }
    }

    // ------------------------------------------------------------------
    // Structural operations
    // ------------------------------------------------------------------

    /// Clears the aggregated value of the root node (discharge).
    ///
    /// The subtrees are left intact; only the pre-computed aggregate at the
    /// root is erased so that it is not accidentally re-used.
    fn discharge(&mut self) {
        if let Tree::Inner { node, .. } = self {
            node.aggregation = None;
        }
    }

    /// Combines two trees `t1` and `t2` under a new inner node whose
    /// aggregate is `op(t1.agg, t2.agg)`.  `t1` is discharged (its stored
    /// aggregate is cleared) before it becomes the left child.
    ///
    /// If either tree is a leaf the other is returned unchanged.
    fn combine<Op>(mut t1: Tree<A>, t2: Tree<A>, op: &Op) -> Tree<A>
    where
        Op: Fn(A, A) -> A,
    {
        match (&t1, &t2) {
            (Tree::Leaf, _) => t2,
            (_, Tree::Leaf) => t1,
            _ => {
                let from = t1.left_index().unwrap();
                let to = t2.right_index().unwrap();
                let agg = lifted_op(t1.node_agg(), t2.node_agg(), op);
                t1.discharge();
                Tree::Inner {
                    node: Node {
                        from,
                        to,
                        aggregation: agg,
                    },
                    left: Box::new(t1),
                    right: Box::new(t2),
                }
            }
        }
    }

    /// Returns a reference to the aggregation stored at the root (for
    /// internal use by `combine`).
    fn node_agg(&self) -> Agg<A> {
        match self {
            Tree::Leaf => None,
            Tree::Inner { node, .. } => node.aggregation.clone(),
        }
    }
}

/// Lifts a binary operator to work on `Option` values: returns `Some(op(x,
/// y))` when both are `Some`, otherwise `None`.
fn lifted_op<A, Op>(x: Agg<A>, y: Agg<A>, op: &Op) -> Agg<A>
where
    Op: Fn(A, A) -> A,
{
    match (x, y) {
        (Some(a), Some(b)) => Some(op(a, b)),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Core algorithm helpers
// ---------------------------------------------------------------------------

/// Folds all *maximal reusable subtrees* of `t` whose index range lies
/// entirely at or after `left_bound` into `acc` via `combine`.
///
/// A subtree is *reusable* for the new window if its entire range `[from,
/// to]` satisfies `from >= left_bound`.  The algorithm walks the tree once,
/// collecting the right-spine nodes that qualify.
fn reusables<A: Clone, Op>(op: &Op, t: Tree<A>, left_bound: usize, mut acc: Tree<A>) -> Tree<A>
where
    Op: Fn(A, A) -> A,
{
    let mut cur = t;
    loop {
        match cur.right_index() {
            // `cur` is a leaf or its range ends before `left_bound` – nothing
            // reusable here.
            None => return acc,
            Some(ri) if left_bound > ri => return acc,
            _ => {}
        }

        if cur.left_index() == Some(left_bound) {
            // The whole subtree is reusable.
            return Tree::combine(cur, acc, op);
        }

        // Descend into children.
        match cur {
            Tree::Leaf => return acc, // shouldn't happen after checks above
            Tree::Inner { left, right, .. } => {
                let t_left = *left;
                let t_right = *right;

                if t_right.left_index().map_or(false, |li| left_bound >= li) {
                    // Entire left subtree is expired; only recurse right.
                    cur = t_right;
                } else {
                    // Right subtree is fully reusable; accumulate it and
                    // recurse left.
                    acc = Tree::combine(t_right, acc, op);
                    cur = t_left;
                }
            }
        }
    }
}

/// Advances one window step.
///
/// Reads new elements from `iter` (elements that fall inside `w` but were
/// not in the previous window), builds singleton trees for them right-to-left
/// so that the leftmost element ends up deepest on the left spine, then
/// combines them with the reusable subtrees from the previous tree `t`.
///
/// Returns `(updated_tree, true)` on success or `(Leaf, false)` if the
/// iterator was exhausted before all required elements were delivered.
///
/// `stream_pos` is the 0-based index of the *next* element that will be
/// yielded by `iter` (i.e., `1 + previous_right_index`, or `0` initially).
fn slide<A: Clone, I: Iterator<Item = A>, Op>(
    op: &Op,
    iter: &mut I,
    stream_pos: &mut usize,
    t: Tree<A>,
    w: Window,
) -> (Tree<A>, bool)
where
    Op: Fn(A, A) -> A,
{
    let prev_right = t.right_index().map_or(0, |r| r + 1); // one past prev window end
    let new_from = w.left.max(prev_right);
    let new_to = w.right;

    // Skip elements that lie between the end of the previous window and the
    // start of the current window (gap elements that belong to neither).
    let skip_count = new_from.saturating_sub(*stream_pos);
    for _ in 0..skip_count {
        if iter.next().is_none() {
            return (Tree::Leaf, false);
        }
        *stream_pos += 1;
    }

    // Collect new elements and build singleton trees right-to-left so that
    // the fold below produces the correct left-spine structure.
    let need = if new_to >= new_from {
        new_to - new_from + 1
    } else {
        0
    };

    let mut new_singletons: Vec<Tree<A>> = Vec::with_capacity(need);
    // Guard against the case where the window's new range is empty
    // (i.e., `new_from > new_to`).  A plain `for idx in new_from..=new_to`
    // would panic on underflow when both are `usize` and `new_from > new_to`.
    if new_from <= new_to {
        for idx in new_from..=new_to {
            match iter.next() {
                Some(v) => {
                    new_singletons.push(Tree::singleton(idx, v));
                    *stream_pos += 1;
                }
                None => return (Tree::Leaf, false),
            }
        }
    }

    // Fold new singletons right-to-left into a single tree, then combine
    // with the reusable subtrees from the previous window.
    let news_tree = new_singletons
        .into_iter()
        .rev()
        .fold(Tree::Leaf, |acc, s| Tree::combine(s, acc, op));

    let result = reusables(op, t, w.left, news_tree);
    (result, true)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// An iterator that computes sliding-window aggregations.
///
/// Constructed via [`SlidingWindow::new`].
///
/// Each call to [`Iterator::next`] consumes one window from `windows`,
/// reads as many elements from `input` as needed, and returns
/// `Some(x[l] op x[l+1] op … op x[r])`.  Returns `None` when `windows` is
/// exhausted or when `input` runs out of elements.
pub struct SlidingWindow<A, I, W, Op>
where
    I: Iterator<Item = A>,
    W: Iterator<Item = Window>,
    Op: Fn(A, A) -> A,
{
    input: I,
    windows: W,
    op: Op,
    tree: Tree<A>,
    /// Index of the next element that will be yielded by `self.input`.
    stream_pos: usize,
}

impl<A, I, W, Op> SlidingWindow<A, I, W, Op>
where
    A: Clone,
    I: Iterator<Item = A>,
    W: Iterator<Item = Window>,
    Op: Fn(A, A) -> A,
{
    /// Creates a new [`SlidingWindow`] iterator.
    ///
    /// # Arguments
    /// * `input`   – iterator over stream elements `x_0, x_1, …`
    /// * `windows` – iterator over `Window { left, right }` values;
    ///               both the `left` and `right` sequences must be
    ///               non-decreasing and `left <= right` must hold for every
    ///               window.
    /// * `op`      – associative binary operator used for aggregation.
    pub fn new(input: I, windows: W, op: Op) -> Self {
        SlidingWindow {
            input,
            windows,
            op,
            tree: Tree::Leaf,
            stream_pos: 0,
        }
    }
}

impl<A, I, W, Op> Iterator for SlidingWindow<A, I, W, Op>
where
    A: Clone,
    I: Iterator<Item = A>,
    W: Iterator<Item = Window>,
    Op: Fn(A, A) -> A,
{
    type Item = A;

    fn next(&mut self) -> Option<Self::Item> {
        let w = self.windows.next()?;

        let old_tree = std::mem::replace(&mut self.tree, Tree::Leaf);
        let (new_tree, ok) = slide(&self.op, &mut self.input, &mut self.stream_pos, old_tree, w);

        if !ok {
            // Input exhausted before the window could be filled.
            return None;
        }

        self.tree = new_tree;
        Some(self.tree.extract().clone())
    }
}

/// Convenience function mirroring the Haskell / OCaml API.
///
/// Aggregates each window `ws[i] = (l, r)` over the slice `xs` using the
/// associative operator `op`, returning a `Vec` of results.
///
/// # Panics
/// Panics if any window index is out of bounds for `xs`.
pub fn sliding_window<A, Op>(xs: &[A], ws: &[Window], op: Op) -> Vec<A>
where
    A: Clone,
    Op: Fn(A, A) -> A,
{
    SlidingWindow::new(xs.iter().cloned(), ws.iter().copied(), op).collect()
}
