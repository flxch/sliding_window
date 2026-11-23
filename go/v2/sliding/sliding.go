package sliding


// Type of an operator over the type T.
type Op[T any] func(T, T) T

// Window of elements within a data stream.  Bounds must be nonnegative and the
// right bound must not be smaller than the left bound.
type Window struct {
    Left  int
    Right int
}

// Type of a function that provides the next element of a stream.  If the
// second return value is false, the stream has no next element.
type Next[T any] func() (T, bool)


// `option[A]` represents an optional value: `ok == true` means that `value` is
// valid and `ok == false` means no value is present.
type option[A any] struct {
    value A
    ok    bool
}

// `some` wraps the value `v` in an option.
func some[A any](v A) option[A] { return option[A]{value: v, ok: true} }

// `none` returns an empty option.
func none[A any]() option[A] { return option[A]{} }

// `isSome` reports whether the option holds a value.
func (o option[A]) isSome() bool { return o.ok }

// `isNone` reports whether the option holds no value.
func (o option[A]) isNone() bool { return !o.ok }

// `lift` wraps the operator `op` so it works on option values: the result is
// some(op(x, y)) when both inputs are some, and none, otherwise.
func lift[A any](op Op[A]) Op[option[A]] {
    return func(x, y option[A]) option[A] {
        if x.isNone() || y.isNone() {
            return none[A]()
        }
        return some(op(x.value, y.value))
    }
}


// `label` holds the data stored at a tree node.  `aggregation` is an option. It
// is `some(v)` for nodes for which the aggregation has already compute from the
// index `from` to the index `to`.  Otherwise, it is `none`, i.e., the
// aggregation has not yet been computed from the index `from` to the index
// `to`.  Indices refer to the positions of the elements in the data stream.
type label[A any] struct {
    from        int       // left index
    to          int       // right index
    aggregation option[A] // aggregated value [from..to]; maybe none
}

// `tree` represents a binary tree where the nodes may carry the aggregated
// value of the subtrees.
//type tree[A any] struct {
//    data  label[A] // aggregated value
//    left  *tree[A] // left child
//    right *tree[A] // right child
//}


// Tree constructors.

// `leaf` returns a leaf.
//func (S *setup[A]) leaf() tree {
//    return leaf
//}

// `singleton` returns the tree with the aggregated value `x` at index `i`.
func (S *setup[A]) singleton[A any](i int, x A) tree {
    t := S.get()
    S.nodes[t].data = label[A]{from: i, to: i, aggregation: some(x)}
    return t
}

// `combine` merges two trees into a new tree whose aggregation is
// `op(t1.aggregation, t2.aggregation)`.  `t1` is discharged and becomes the
// left child and `t2` becomes the right child.  If either tree is a leaf the
// other is returned as is.
func (S *setup[option[A]]) combine(t1, t2 tree) tree {
    switch {
    case S.isLeaf(t1):
        return t2
    case S.isLeaf(t2):
        return t1
    default:
        t := S.get()
        S.nodes[t].data = label[A]{
            from:        S.nodes[t1].data.from,
            to:          S.nodes[t2].data.to,
            aggregation: S.op(S.nodes[t1].data.aggregation, S.nodes[t2].data.aggregation),
        }
        S.nodes[t].left, S.nodes[t].right = discharge(t1), t2
        return t
    }
}

// `isLeaf` returns true if `t` is a leaf.
// (Helper function in `combine` above and the selectors below.)
func (S *setup[A]) isLeaf(t tree) bool {
    return t == leaf
}

// `discharge` returns `t` with its aggregation cleared to none.  Note that
// `discharge` is not side-effect free.  The order in which it is called with
// other functions might be important.
// (Helper function in `combine`.)
func (S *setup[A]) discharge(t tree) tree {
    S.nodes[t].data.aggregation = none[A]()
    return t
}

// Tree selectors.

func (S *setup[A]) leftIndex(t tree) int {
    if S.isLeaf(t) {
        panic("leaves have no left indices")
    }
    return S.nodes[t].data.from
}

func (S *setup[A]) rightIndex(t tree) int {
    if S.isLeaf(t) {
        return -1
    }
    return S.nodes[t].data.to
}

func (S *setup[A]) extract(t tree) A {
    if S.isLeaf(t) || S.nodes[t].data.aggregation.isNone() {
        // The extract function should never be called for leaves or when
        // the aggregation has not been computed yet.
        panic("no aggregated value at the tree's root")
    }
    return S.nodes[t].data.aggregation.value
}

func (S *setup[A]) children(t tree) (tree, tree) {
    return S.nodes[t].left, S.nodes[t].right
}

// Auxiliary tree functions.

// `news` reads `n` new elements from `ch` starting at index `i`, combines them
// into a tree right-to-left (so that the leftmost element ends up deepest on
// the left spine), and folds the result into `acc`.  It returns the updated
// accumulator and true, or acc unchanged and false if the channel was closed
// before all elements were read.
func (S *setup[A]) news(i, n int, acc tree) (tree, bool) {
    if n <= 0 {
        // Done; all elements for the windows have have been received.
        return acc, true
    }

    // Read next element from the input channel.
    v, ok := <-S.in
    if !ok {
        // Input channel closed; signal termination.
        return acc, false
    }
    // Aggregate value.
    if acc, ok = S.news(i + 1, n - 1, acc); !ok {
        // Input channel closed; signal termination.
        return acc, false
    }
    return S.combine(S.singleton(i, v), acc), true
}

// `reusables` folds every maximal subtree of `t` whose index range lies
// entirely at or after `i` into `acc` via `combine`.  The tail-recursive
// implementation was replaced by an implementation with a for loop.
func (S *setup[A]) reusables(t tree, i int, acc tree) tree {
    for {
        if i > S.rightIndex(t) {
            return acc
        }
        if i == S.leftIndex(t) {
            return S.combine(t, acc)
        }
        if t1, t2 := S.children(t); i >= S.leftIndex(t2) {
            t = t2 // tail call: reusables(op, t2, l, acc)
            S.put(t1)
        } else {
            acc = S.combine(t2, acc)
            t = t1 // tail call: reusables(op, t1, l, acc)
        }
    }
}

// `slide` advances the tree `t` by one window step.  It returns the updated
// tree by aggregating the elements in the window `w` with the operation `op`
// and true on success, or a leaf and false if the input channel was closed
// before all elements within the window `w` were received.
func (S setup[A]) slide(t tree, w Window) (tree, bool) {
    from, to := max(w.Left, 1 + S.rightIndex(t)), w.Right

    // Skip elements that are after the previous window and before the current
    // window.  These elements have not yet been read from the input channel.
    if ok := S.skip(from - (1 + S.rightIndex(t))); !ok {
        // Input channel closed; signal termination.
        return leaf, false
    }

    // Loop 1: Fold newly received elements directly that were not contained in
    // the previous window.
    r, ok := S.news(from, max(0, to - from + 1), leaf)
    if !ok {
        // Input channel closed; signal termination.
        return leaf, false
    }
    // Loop 2: Fold the reusable subtrees from the previous window's tree.
    return S.reusables(t, w.Left, r), true
}

// `skip` discards the next `k` elements from the channel `ch`.  It returns
// false if the channel was closed before `k` elements were received.
// (Helper function in `slide`.)
func (S *setup[A]) skip(k int) bool {
    for range k {
        if _, ok := <-S.in; !ok {
            return false
        }
    }
    return true
}


// `SlidingWindow` computes the aggregations of stream elements within a
// sliding window for an associative operator.
// - `in`:   a channel delivering x0, x1, x2, ... in order (may be infinite)
//           `SlidingWindow` reads the elements from `in` only as far as
//           required by the windows seen so far.
// - `out`:  a channel on which results y0, y1, ... are sent, where
//           yi = x[li] op x[li+1] op ... op x[ri].
//           Note that the caller/creator is responsible for closing the channel.
// - `op`:   a binary operator, which is assumed to be associative.
// - `next`: a function returning the next window and true, or false when the
//           window sequence is exhausted; the windows must satisfy the following
//           conditions (i.e., windows always move to the right):
//           0 <= l0 <= l1 <= ...  and  0 <= r0 <= r1 <= ...  and  li <= ri
func SlidingWindow[A any](in <-chan A, out chan<- A, op Op[A], next Next[Window]) {
    S := newSetup(in, op, l)
    t := leaf

    for {
        // Get next window.
        w, ok := next()
        if !ok {
            // No windows anymore.  Stop.
            return
        }
        // Compute aggregation.
        if t, ok = S.slide(t, w); !ok {
            // No more input elements.  Stop.
            return
        }
        // Send aggregated value.
        out <- S.extract(t)
    }
}
